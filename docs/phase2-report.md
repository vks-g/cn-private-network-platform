# Phase 2 report: Harden, Recover, Troubleshoot

Phase 2 uses the same four UTM VMs, subnet and names as Phase 1 (see [architecture.md](architecture.md)); nothing was rebuilt. It adds:

- a backup DNS server;
- a short DNS TTL;
- backend firewall rules;
- tested HA failover;
- a standby edge with a DNS cutover;
- a layer-by-layer diagnosis method.

Evidence is in [`evidence/phase2/`](../evidence/phase2/): 19 numbered screenshots, plus the raw terminal text of each one in `raw/`. All tests ran on 23 Nov 2026.

## 1. What changed from Phase 1

| Area | Phase 1 | Phase 2 |
| --- | --- | --- |
| DNS servers | vm1 only | vm1 primary + vm3 backup, same records file |
| Client resolvers | `192.168.64.11` | `192.168.64.11`, then `192.168.64.13` (vm2–vm4 netplan, Mac `/etc/resolver`) |
| Record TTL | 0 (`address=`, never cached) | 30 s (`host-record=…,30`) |
| Backend ports 3001/3002 | open to the whole LAN | only the edge `192.168.64.12` (nftables, demonstrated and rolled back) |
| Backend failure | nginx passive health check configured | tested: failover, recovery, and the edge shown as the remaining SPOF |
| Edges | vm2 only | vm2 active + vm3 standby with the same nginx file and its own CA-signed certificate; `X-Edge` header on every response |
| Diagnosis | ad hoc | [`scripts/diagnose.sh`](../scripts/diagnose.sh) + [runbook](troubleshooting.md) |

The brief asks for macOS `pf` rules. Our backends are Ubuntu VMs, so we use `nftables`, the Linux packet filter that does the same job.

## 2. Resilience tests and results

| # | Test | Expected | Observed | Evidence |
| --- | --- | --- | --- | --- |
| A1 | Backup server answers the same records | `dig @.13` = `dig @.11` | both return `app.teamvks.test → 192.168.64.12`, TTL 30 | [01](../evidence/phase2/01-dns-backup-server-on-vm3.png) |
| A2 | Clients know both servers | `.11` first, `.13` second | vm4 `resolvectl`: `DNS Servers: 192.168.64.11 192.168.64.13`; Mac `scutil --dns`: `nameserver[0] .11`, `nameserver[1] .13` | [02](../evidence/phase2/02-dns-clients-list-both-servers.png) |
| A3 | Primary DNS stopped (vm1) | clients keep resolving | `dig @.11` → connection refused. tcpdump on vm4: query to `.11` → ICMP port unreachable → same query to `.13` 0.1 ms later → answer `.12` (3.5 ms in total). HTTPS 200; `Current DNS Server: 192.168.64.13` | [03](../evidence/phase2/03-dns-failover-primary-down.png) |
| A4 | DNS failure vs application failure | different symptoms | **Both DNS servers down:** `curl: (6) Could not resolve host`, but `ping .12` 0 % loss and HTTPS by IP (`--resolve`) 200. **DNS up, both backends down:** the name resolves, the edge returns `502 Bad Gateway`, and `error.log` shows `connect() failed (111: Connection refused)` for both upstreams | [04](../evidence/phase2/04-dns-failure-vs-app-failure.png) |
| C1 | Isolation rule loaded with a rollback copy | rule active, copy saved | the ruleset was empty before (copy = 0 lines); the table `inet teamvks_isolation` is loaded on vm3 and vm4 | [05](../evidence/phase2/05-isolation-rule-and-rollback-copy.png) |
| C2 | Only the edge reaches the backends | clients blocked, edge allowed | vm1 and the Mac: `Failed to connect … after 3004 ms: Timeout` on 3001 and 3002 (dropped, not refused). vm2: 200 from both. HTTPS through the edge still alternates A/B. vm3 counters: 17 packets accepted from the edge, 6 dropped | [06](../evidence/phase2/06-isolation-before-after.png) |
| C3 | Rollback | original state | table deleted on both; `nft list ruleset \| diff - ~/nft-rollback.rules` is empty; vm1 and the Mac get 200 directly again | [07](../evidence/phase2/07-isolation-rollback.png) |
| D1 | Backend A stopped | all requests still succeed | 10/10 `HTTP/2 200 x-backend: B`. In the access log the first request shows `upstream=192.168.64.13:3001, 192.168.64.14:3002 upstream_status=502, 200`: nginx retried it on B within the same request. The next nine go straight to B | [08](../evidence/phase2/08-ha-backend-a-down.png) |
| D2 | Backend A restarted | round-robin resumes | after `fail_timeout` (10 s) the access log alternates `13:3001` / `14:3002` again | [09](../evidence/phase2/09-ha-backend-a-recovered.png) |
| D3 | Edge stopped (vm2) | edge = single point of failure | DNS still answers `.12`, both backends return 200 directly, yet `curl` gets `Failed to connect … port 443: Couldn't connect to server` | [10](../evidence/phase2/10-ha-edge-is-spof.png) |
| E1 | Standby edge on vm3 | same service, own certificate | `Verify return code: 0 (ok)` and issuer `teamvks Lab Root CA`; via `--resolve` to `.13`: 200, A/B alternate, `x-edge: vm3-backend-a`. DNS still points to vm2 | [11](../evidence/phase2/11-standby-edge-on-vm3.png) |
| B1 / E2 | Record moved to `.13` at 12:11:30 | cached clients stay on the old edge until the TTL expires | **vm1 (no cache):** `.13` and `x-edge: vm3-backend-a` at once. **vm4 (caching client):** kept `192.168.64.12` while its cached TTL fell 30 → 24 → … → 4 s (12:11:21–12:11:46). At 12:11:51 it fetched `.13` with a new TTL of 30 and moved to vm3 | [12](../evidence/phase2/12-cutover-ttl-countdown.png) |
| E3 | Both edges serve during the change | traffic split by cache state | **vm2 log:** vm4 up to 12:11:46. **vm3 log:** 1 request from vm1 (at once) and 7 from vm4 (after its TTL expired) | [13](../evidence/phase2/13-cutover-access-logs.png) |
| B2 | Manual cache flush | immediate change | after the cutback the server already answered `.12`, while vm4's cache still returned `.13` (TTL 27 s left). `resolvectl flush-caches` → `.12` and `x-edge: vm2-edge` at once | [14](../evidence/phase2/14-cutback-flush-cache.png) |
| — | Final state | everything restored | `diagnose.sh` passes all 4 layers from vm4 and vm1; A/B alternate; live configs `diff` clean against the repo; no firewall table left | [19](../evidence/phase2/19-final-state-all-layers-pass.png) |

## 3. Troubleshooting findings

### Drills (practice for the faculty-injected fault)

Each fault was injected by hand, found with [`diagnose.sh`](../scripts/diagnose.sh) from vm4, and fixed by reinstalling the file from the repo. The script stops at the first broken layer, and its exit code is the number of that layer.

| Drill | Fault injected | First failing layer (exit code) | Signature | How the cause was found | Fix | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `app.teamvks.test` misspelt `teamvsk` in the records file on both servers | DNS (1) | `NXDOMAIN` from `.11` and `.13`, so this is not a server outage | `diff` of the live records file against the repo shows line 17 | reinstall the records file, restart dnsmasq on vm1 + vm3 | [15](../evidence/phase2/15-drill-dns-record-typo.png) |
| 2 | nginx stopped on vm2 | TCP (2) | DNS PASS; `connection refused (TCP RST)`, while the host still answers ping | `ss -ltn 'sport = :443'` → nothing listening; `systemctl is-active nginx` → inactive | `nginx -t`, start nginx | [16](../evidence/phase2/16-drill-tcp-nginx-stopped.png) |
| 3 | nginx pointed at a throwaway self-signed certificate | TLS (3) | DNS and TCP PASS; issuer = subject, `SAN: none`, `self-signed certificate` | `diff` of the site file against the repo shows the changed `ssl_certificate` lines | reinstall the site file, reload, delete the throwaway cert | [17](../evidence/phase2/17-drill-tls-self-signed.png) |
| 4 | upstream ports mistyped (3011, 3012) | HTTP (4) | DNS, TCP and TLS PASS; `502 Bad Gateway from edge vm2-edge` | `error.log`: `connect() failed (111) … upstream: http://192.168.64.13:3011` | reinstall the site file, reload | [18](../evidence/phase2/18-drill-http-upstream-port.png) |

### What we learned while running the tests

- **Refused vs timeout tells you what is in the way.** A stopped service answers with a TCP reset at once: `refused`, as in drill 2 and test D3. A firewall `drop` sends nothing back, so the client waits for its timeout, as in test C2. DNS showed the same pattern: a stopped dnsmasq made its host return an ICMP "port unreachable", so systemd-resolved switched to the backup within about 0.1 ms instead of waiting for a timeout (test A3).
- **The Phase 1 clients had no DNS cache.** In Phase 1 `/etc/resolv.conf` on the VMs was pointed straight at `192.168.64.11`, so `dig` would show our server. This means `curl` asks the DNS server every time and ignores the TTL.
  - For the TTL and cutover tests, vm4 was switched to the systemd-resolved stub (`127.0.0.53`, Ubuntu's default), which caches answers like a normal desktop or browser. It was switched back afterwards.
  - vm1 stayed without a cache, which is why it moved to the standby at once in test B1/E2.
- **HA can hide a fault.** In test D1 a refused backend was retried on the other one within the same request, so the client saw 200. A single wrong upstream port would therefore not be visible to users at all, only in `error.log`. Drill 4 needed both ports wrong to produce a 502. In the live challenge we read `error.log` even when the HTTP layer passes.
- **`systemctl reload nginx` is not instant.** Old workers finish their requests first. One request sent right after the reload still came from the old configuration: the new `X-Edge` header was missing. We wait a second after a reload before testing.
- **Isolation and migration interact.** The firewall rule allows only `192.168.64.12`.
  - If it were active during the cutover, the standby edge on vm3 could still reach its own Backend A (the traffic stays on the loopback interface, which the rule accepts).
  - Its requests to Backend B on vm4 would be dropped. The rule on vm4 would need the standby's address too.

## 4. Learning summary

**A – Backup DNS.** A DNS failure and an application failure look the same to a user ("the site is down"), but they are different layers.

- **DNS failure:** the client never gets an IP. `curl` stops at "Could not resolve host" before any packet reaches the edge. Meanwhile `ping 192.168.64.12` and HTTPS by IP still work, so the network and the service are fine and only the "directory" is missing.
- **Application failure:** DNS and TLS still succeed and the edge itself answers with 502. The failure is behind the edge.

A second DNS server only helps if clients know about it, so the resolvers list two servers. When the primary was stopped, systemd-resolved got a refusal from `.11` and asked `.13` straight away. The two servers must serve identical data. Real DNS keeps a secondary in sync with zone transfers; we install the same records file on both.

**B – TTL and record changes.** The TTL is how long a resolver may reuse an answer without asking again.

- While a cached answer is valid, a changed record is invisible to that client, even though the server already gives the new IP. In our test vm4 kept the old edge until its cached TTL had counted down from 30 to 0, and only then fetched the new address.
- Flushing the cache (`resolvectl flush-caches`) made it switch at once.
- In production, a team lowers the TTL well before a migration, so caches expire quickly when the record changes, and raises it again afterwards. Short TTLs give faster changes but more queries and more dependence on the DNS servers.

**C – Service isolation.** The backends never needed to be reachable by clients; only the edge talks to them. Allowing ports 3001/3002 only from `192.168.64.12` makes the edge the single entry point, so TLS, logging and load balancing cannot be bypassed.

- A firewall rule works below the application. Each packet is checked by source address and destination port before the backend process sees anything; the counters show the edge's packets accepted and the clients' packets dropped.
- We drop instead of reject. A blocked client sees a timeout, while a stopped backend answers "connection refused", so the error tells you whether a firewall or a missing service is in the way.
- The rule is runtime-only with a saved rollback copy, so restoring the original state is one command plus a `diff` check.
- This is what cloud security groups do between a load balancer and its targets.

**D – High availability.** nginx uses passive health checks. When a backend refuses a connection, it is marked failed (`max_fails=1`) and skipped for `fail_timeout=10s`. `proxy_next_upstream` retries the same request on the other backend, so the client still gets 200 and never sees the failure. The access log shows both attempts. After the timeout, nginx tries the backend again with real traffic, and once it answers, round-robin resumes.

The backends are now redundant, but the edge is not: stopping nginx on vm2 took the whole service down while DNS and both backends were healthy. Removing that single point of failure needs a second edge that takes over the same address automatically: a keepalived/VRRP floating IP on a LAN, or a managed multi-zone load balancer in the cloud.

**E – Edge migration by DNS.** A standby edge is useless until clients are sent to it, and DNS is how clients find the edge. When `app.teamvks.test` was pointed at vm3:

- a client without a cache (vm1) moved at once;
- a client with a cached answer (vm4) kept using vm2 until its TTL ran out.

During that window both edges served traffic, so the old edge must stay up for at least one TTL after the change (connection draining). The standby needs its own certificate for the same names, because a certificate is bound to names, not IPs. Ours was signed by the same CA from a key that never left vm3. This is how blue/green deployments and DNS-based traffic migration work in production.

**F – Systematic diagnosis.** Check the layers in the order a request uses them: DNS, TCP, TLS, HTTP. Each layer only works if the ones below it work, so the first failing check names the fault and saves guessing.

The exact error wording matters:

| Layer | Message | Meaning |
| --- | --- | --- |
| DNS | NXDOMAIN | there is no such record |
| DNS | timeout | no server answered |
| TCP | refused | nothing is listening |
| TCP | timeout | packets are being dropped |
| TLS | self-signed / unable to get local issuer | the certificate is not trusted |
| TLS | hostname mismatch | the certificate is for a different name |
| HTTP | 502 | the edge cannot reach a backend |
| HTTP | 504 | the backend answered too slowly |

[`diagnose.sh`](../scripts/diagnose.sh) runs these checks automatically, and the [runbook](troubleshooting.md) lists the commands and the signature of each likely fault. In all four drills, comparing the live file with the repo copy (`diff`) found the exact line that had changed.

## 5. Re-run it live (demo steps 8–10)

Each block is labelled with the VM pane it runs in. Phase 2 state at the start: both DNS servers running, records → `.12` with TTL 30, nginx running on vm2 and (standby, not in DNS) on vm3, no firewall table.

### Step 8: fail one backend, service continues (Extension D)

```bash
# vm3
sudo systemctl stop teamvks-backend
# vm4  (all 200, all B)
for i in $(seq 6); do curl -si https://app.teamvks.test/api/status | tr -d '\r' | grep -iE '^HTTP|x-backend' | paste -sd' '; done
# vm2  (first line: upstream=...13:3001, ...14:3002 upstream_status=502, 200)
sudo tail -n 6 /var/log/nginx/teamvks-access.log
# vm3
sudo systemctl start teamvks-backend
# vm4  (after ~10 s: A and B alternate again)
sleep 10; for i in $(seq 6); do curl -si https://app.teamvks.test/api/status | grep -i x-backend; done
# Edge = single point of failure. vm2: sudo systemctl stop nginx; vm4: curl fails;
# vm2: sudo systemctl start nginx
```

### Step 9: DNS resilience (Extensions A, B, E)

Backup DNS (A):

```bash
# vm1
sudo systemctl stop dnsmasq
# vm4
dig @192.168.64.11 app.teamvks.test +tries=1 +time=2        # fails: connection refused
sudo resolvectl flush-caches; curl -sI https://app.teamvks.test/api/status | head -1   # still 200
resolvectl status enp0s1 | grep 'Current DNS'               # 192.168.64.13
# vm1
sudo systemctl start dnsmasq
```

TTL + cutover to the standby edge (B, E):

```bash
# vm4: use the caching stub resolver for this demo, then watch
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf && sudo resolvectl flush-caches
bash ~/cn/scripts/watch-cutover.sh app.teamvks.test 12 5
# vm1 AND vm3, within the first 10 s of the watch
sudo sed -i 's/,192.168.64.12,30/,192.168.64.13,30/' /etc/dnsmasq.d/teamvks-records.conf && sudo systemctl restart dnsmasq
# vm1: a client without a cache moves at once
dig +short app.teamvks.test; curl -sI https://app.teamvks.test/api/status | grep -i x-edge
# vm4 output: .12 with the TTL counting down, then .13 and x-edge vm3-backend-a
```

Cutback + manual flush (B):

```bash
# vm1 AND vm3
sudo install -m 644 ~/cn/configs/common/dnsmasq/teamvks-records.conf /etc/dnsmasq.d/ && sudo systemctl restart dnsmasq
# vm4
dig @127.0.0.53 +noall +answer app.teamvks.test             # still .13 (cached)
sudo resolvectl flush-caches; dig @127.0.0.53 +noall +answer app.teamvks.test   # .12 at once
sudo ln -sf ../run/systemd/resolve/resolv.conf /etc/resolv.conf                  # back to the Phase 1 setup
```

Service isolation (C), if asked:

```bash
# vm3 (vm4: same with vm4-backend-b)
sudo nft list ruleset | tee ~/nft-rollback.rules >/dev/null
sudo nft -f ~/cn/configs/vm3-backend-a/nftables/teamvks-isolation.nft
# vm1: curl --connect-timeout 3 http://192.168.64.13:3001/api/status   -> timeout
# vm2: curl http://192.168.64.13:3001/api/status                        -> 200
# rollback
sudo nft delete table inet teamvks_isolation && sudo nft list ruleset | diff - ~/nft-rollback.rules && echo restored
```

### Step 10: faculty-injected fault (Extension F)

```bash
# vm4 (or vm1): find the broken layer, then follow the runbook for that layer
bash ~/cn/scripts/diagnose.sh app.teamvks.test; echo "exit=$?"
# the faulty machine: compare the live config with the repo
diff ~/cn/configs/vm2-edge/nginx/teamvks.conf /etc/nginx/sites-available/teamvks
diff ~/cn/configs/common/dnsmasq/teamvks-records.conf /etc/dnsmasq.d/teamvks-records.conf
```

Say each step out loud, as in [troubleshooting.md](troubleshooting.md#what-to-say-while-diagnosing): DNS first, then TCP (refused or timeout), then TLS (verify code), then HTTP (status code + `error.log`). Then fix the fault and run `diagnose.sh` again until all four layers pass.
