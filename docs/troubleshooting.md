# Troubleshooting runbook (Extension F)

When something breaks, check the layers **in the order a request uses them**. The first layer that fails is where the fault is. Everything above it is unreachable and tells you nothing yet.

```text
1 DNS   name -> IP          dig, resolvectl
2 TCP   IP:port reachable?  bash /dev/tcp, nc, ss
3 TLS   handshake + cert    openssl s_client, curl -v
4 HTTP  status + headers    curl -sI, nginx error.log, backend journal
```

## One command first

From a client VM (vm4 or vm1):

```bash
bash ~/cn/scripts/diagnose.sh app.teamvks.test
```

It runs the four checks, prints PASS/FAIL for each and stops at the first failure with the likely causes. The exit code is the broken layer (1 DNS, 2 TCP, 3 TLS, 4 HTTP; 0 all fine). Then confirm by hand with the commands below and say out loud what each one proves.

**Find the changed line.** Every live config was installed from the repo, so on the faulty machine a `diff` shows exactly what was changed:

```bash
diff ~/cn/configs/common/dnsmasq/teamvks-records.conf /etc/dnsmasq.d/teamvks-records.conf   # vm1, vm3
diff ~/cn/configs/vm2-edge/nginx/teamvks.conf /etc/nginx/sites-available/teamvks             # vm2 (and vm3 standby)
```

**HA can hide a fault.** If only one backend is broken (stopped, wrong port), nginx retries the other and clients still get 200. `diagnose.sh` passes, but `sudo tail /var/log/nginx/error.log` on vm2 shows the failing upstream. Check it even when everything passes.

Drills run with this method: [phase2-report.md §3](phase2-report.md#3-troubleshooting-findings), screenshots 15–18.

## By hand, layer by layer

| # | Question | Command (client unless noted) | Good | Bad means |
| --- | --- | --- | --- | --- |
| 1 | Does the name resolve? | `dig app.teamvks.test` · `dig @192.168.64.11 app.teamvks.test` · `dig @192.168.64.13 app.teamvks.test` | `ANSWER: 192.168.64.12`, status `NOERROR` | `NXDOMAIN` = no such record (typo, deleted record); no reply/timeout = dnsmasq down or wrong resolver; wrong IP = bad record |
| 1 | Which server is this client using? | `resolvectl status enp0s1` | `Current DNS Server: 192.168.64.11` (or `.13` after a failover) | a server that is not ours (e.g. 8.8.8.8) = wrong resolver config |
| 2 | Is the host up? | `ping -c2 192.168.64.12` | replies | no reply = VM down or wrong IP (or ICMP blocked) |
| 2 | Does the port accept connections? | `timeout 3 bash -c '</dev/tcp/192.168.64.12/443' && echo open` | `open` | **refused** = host up, nothing listening (nginx stopped, wrong `listen` port); **timeout** = packets dropped (firewall) or host down |
| 2 | (edge) What is listening? | vm2: `sudo ss -ltnp \| grep nginx` · `systemctl status nginx` | `*:443` and `*:80` | port missing = wrong `listen` line or nginx failed to start (`sudo nginx -t`) |
| 3 | Does TLS work and verify? | `openssl s_client -connect 192.168.64.12:443 -servername app.teamvks.test -verify_hostname app.teamvks.test </dev/null \| grep -E 'subject=\|issuer=\|Verify return'` | `Verify return code: 0 (ok)` | `self-signed` / `unable to get local issuer` = cert not from our CA or CA not trusted; `hostname mismatch` = SAN lacks the name; `expired`; no handshake = no `ssl` on the listen line |
| 4 | What does HTTP return? | `curl -sI https://app.teamvks.test/api/status` | `200`, `x-backend: A/B`, `x-edge: vm2-edge` | `502` = edge cannot reach any backend; `504` = backend did not answer in time; `404` = wrong path or `location` |
| 4 | (edge) Why 502/504? | vm2: `sudo tail -n 20 /var/log/nginx/error.log` | – | `connect() failed (111: Connection refused) … upstream: http://IP:PORT` = backend down or wrong port in `upstream`; `timed out` = firewall drop or hung backend |
| 4 | (backend) Is the app up? | vm3/vm4: `systemctl status teamvks-backend` · `curl -s localhost:3001/api/status` | `active (running)`, JSON | stopped/crashed: `journalctl -u teamvks-backend -n 20` |

## Likely injected faults and their signature

| Fault | Layer | What you see | Fix |
| --- | --- | --- | --- |
| dnsmasq stopped on vm1 | 1 (masked) | still works: clients fail over to vm3 (`resolvectl` shows `.13`) | `sudo systemctl start dnsmasq` |
| dnsmasq stopped on both | 1 | `curl: (6) Could not resolve host`; `dig @…` times out; `ping 192.168.64.12` still works | start dnsmasq |
| Record typo / deleted | 1 | `NXDOMAIN` from both servers | fix `host-record` in `/etc/dnsmasq.d/teamvks-records.conf`, restart dnsmasq on vm1 **and** vm3 |
| Record points to a wrong IP | 1 → 2 | DNS "works" but TCP times out or reaches the wrong machine | fix the IP in the record |
| Client resolver changed (e.g. 8.8.8.8) | 1 | `NXDOMAIN` on that client only; other clients fine | netplan `nameservers` → `sudo netplan apply` |
| nginx stopped | 2 | DNS fine, ping fine, `Connection refused` on 443 | `sudo systemctl start nginx` |
| nginx `listen` port changed | 2 | refused on 443, `ss -ltnp` shows the other port | fix `listen`, `sudo nginx -t && sudo systemctl reload nginx` |
| Firewall dropping 443 | 2 | TCP **timeout** (not refused) | `sudo nft list ruleset`, delete the rule |
| Wrong certificate / key | 3 | TCP fine, verify error (`self-signed`, `hostname mismatch`) or nginx fails `nginx -t` | point `ssl_certificate*` back to `/etc/nginx/tls/teamvks-server.*` |
| CA not trusted on the client | 3 | `unable to get local issuer certificate` on that client only | `sudo update-ca-certificates` with `teamvks-ca.crt` |
| Both backends stopped | 4 | TLS fine, `502 Bad Gateway`, error.log `Connection refused` | `sudo systemctl start teamvks-backend` on vm3 and vm4 |
| Wrong upstream IP/port | 4 | `502` every time even though backends run; error.log names the bad `IP:PORT` | fix `upstream`, reload nginx |
| Backend port firewalled from the edge | 4 | `504`/`502` after a 2 s connect timeout; error.log `upstream timed out` | remove the nft rule or allow `192.168.64.12` |

## What to say while diagnosing

1. "I start at DNS because nothing else can work without an IP." Show `dig`.
2. "DNS answers, so the problem is below the application but above DNS: is the edge reachable?" Show TCP. Say what **refused** vs **timeout** means.
3. "TCP connects, so check TLS: does the certificate verify for this name?"
4. "TLS works, so the edge itself is fine; a 502 means the edge cannot reach a backend." Show the error.log line, fix it, run `diagnose.sh` again until all four layers pass.
