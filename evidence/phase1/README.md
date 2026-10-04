# Phase 1 evidence

Every file here maps to a form question or a task in the project brief.

- `.txt` files are raw terminal output, saved with `tee` while the commands ran.
- `.png` files are screenshots of the same runs.
- Captures were taken on 3 October 2026 on the lab described in [docs/architecture.md](../../docs/architecture.md).

Ready-to-paste form text is in [form-answers.md](form-answers.md).

## A – Private LAN (Task A · form A1, A5)

Folder: [`A-lan-dns/`](A-lan-dns/)

| Form / brief item | File | What it shows |
| --- | --- | --- |
| A1 machine IPs and roles | [A1-inventory.txt](A-lan-dns/A1-inventory.txt) · [A1-inventory-terminal.png](A-lan-dns/A1-inventory-terminal.png) | hostname, IPv4/prefix, interface, MAC and default gateway of all four VMs |
| A1 | [A1-four-vms-terminal.png](A-lan-dns/A1-four-vms-terminal.png) | one SSH pane per VM: `hostname` and `ip -br addr` side by side |
| A1 | A1-utm-network-vm[1-4].png ([vm1](A-lan-dns/A1-utm-network-vm1.png) · [vm2](A-lan-dns/A1-utm-network-vm2.png) · [vm3](A-lan-dns/A1-utm-network-vm3.png) · [vm4](A-lan-dns/A1-utm-network-vm4.png)) | UTM: four ARM64 VMs on Shared Network, each with its own MAC |
| A5 ping between all pairs | [A5-ping-matrix.txt](A-lan-dns/A5-ping-matrix.txt) · [A5-ping-matrix.png](A-lan-dns/A5-ping-matrix.png) | all 6 VM→VM pairs: 4/4 replies, 0% loss, TTL 64 (no router in between) |
| Layer 2 (ARP) | [A5-arp-table-vm1.txt](A-lan-dns/A5-arp-table-vm1.txt) · [A5-arp-table-vm1.png](A-lan-dns/A5-arp-table-vm1.png) | vm1's ARP cache: each peer IP maps to the MAC in the inventory |
| Switch behaviour | [A-bridge100-switch-table.png](A-lan-dns/A-bridge100-switch-table.png) | `ifconfig bridge100`: one `vmenet` member port per VM and the switch's MAC address table |
| Capture point | [A-wireshark-bridge100-broadcast-only.png](A-lan-dns/A-wireshark-bridge100-broadcast-only.png) | on `bridge100` only the broadcast ARP request is visible; unicast VM↔VM frames never reach the Mac's port |
| ARP + ICMP on the wire | [A-wireshark-vmenet0-arp-icmp.png](A-lan-dns/A-wireshark-vmenet0-arp-icmp.png) | on vm2's port: ARP request (broadcast), ARP reply (unicast), 3 ICMP echo request/reply pairs, Ethernet II → IPv4 → ICMP expanded |

## A – Private DNS (Task B · form A2, A3, A4)

Folder: [`A-lan-dns/`](A-lan-dns/). Server: dnsmasq on vm1-dns (`192.168.64.11`). Records: `app.teamvks.test`, `api.teamvks.test` → `192.168.64.12` (the edge).

| Form / brief item | File | What it shows |
| --- | --- | --- |
| Upstream check | [A2-upstream-check.png](A-lan-dns/A2-upstream-check.png) | the Mac's forwarder (`192.168.64.1`) answers before dnsmasq relies on it |
| Port 53 conflict | [A2-dnsmasq-port53-before.png](A-lan-dns/A2-dnsmasq-port53-before.png) | fresh install: dnsmasq fails with "Address already in use"; `systemd-resolve` owns `127.0.0.53:53` |
| A2 dnsmasq configuration | [A2-dnsmasq-conf.txt](A-lan-dns/A2-dnsmasq-conf.txt) · [full commented file](../../configs/vm1-dns/dnsmasq.d/teamvks.conf) | `interface=`, `listen-address=192.168.64.11`, `bind-dynamic`, `local=`, both `address=` lines, forwarding |
| A2 deploy | [A2-dnsmasq-deploy.png](A-lan-dns/A2-dnsmasq-deploy.png) | `dnsmasq --test` OK, service `active` + `enabled` |
| A2 listening sockets | [A2-dnsmasq-port53-after.png](A-lan-dns/A2-dnsmasq-port53-after.png) | dnsmasq on `192.168.64.11:53` next to systemd-resolved on `127.0.0.53:53` |
| A2 query log | [A2-dnsmasq-query-log.txt](A-lan-dns/A2-dnsmasq-query-log.txt) | `query[A] app.teamvks.test from 192.168.64.14` → `config … is 192.168.64.12`; other names `forwarded … to 192.168.64.1` and `cached` |
| Server tests | [A3-dig-at-server-app.png](A-lan-dns/A3-dig-at-server-app.png) · [A3-dig-at-server-nxdomain-and-lan.png](A-lan-dns/A3-dig-at-server-nxdomain-and-lan.png) | authoritative answer (`aa`), forwarding, `NXDOMAIN` for unknown names in our zone, reachable from vm4 |
| Client resolver setup | [A3-resolv-conf-symlink-ra-dns.png](A-lan-dns/A3-resolv-conf-symlink-ra-dns.png) · [A3-resolv-conf-after-fix.png](A-lan-dns/A3-resolv-conf-after-fix.png) | `/etc/resolv.conf` re-pointed from `127.0.0.53` to the real server; the Mac's IPv6 router-advert DNS removed with `accept-ra: false`; all four VMs end with only `nameserver 192.168.64.11` |
| A3 dig from a client | [A3-dig-app-from-vm4.txt](A-lan-dns/A3-dig-app-from-vm4.txt) · [A3-dig-api-from-vm4.txt](A-lan-dns/A3-dig-api-from-vm4.txt) · [A3-dig-app-from-vm2.txt](A-lan-dns/A3-dig-app-from-vm2.txt) · [A3-A4-dig-from-vm4.png](A-lan-dns/A3-A4-dig-from-vm4.png) | two clients (vm4, vm2): `NOERROR`, `aa`, `app.teamvks.test. 0 IN A 192.168.64.12`, `SERVER: 192.168.64.11#53 (UDP)` |
| Third client: the Mac | [A3-mac-resolver.png](A-lan-dns/A3-mac-resolver.png) | `/etc/resolver/teamvks.test` sends only `*.teamvks.test` to `192.168.64.11`; the system resolver returns `192.168.64.12`; `ping app.teamvks.test` works by name |
| A4 public DNS | [A4-dig-8.8.8.8-nxdomain.txt](A-lan-dns/A4-dig-8.8.8.8-nxdomain.txt) | `status: NXDOMAIN` from 8.8.8.8, root-zone SOA in AUTHORITY, `ad` (DNSSEC-validated non-existence) |

## B – Backend services (Task C)

Folder: [`B-https-lb/`](B-https-lb/). Code: [backend/server.py](../../backend/server.py), run by [teamvks-backend.service](../../backend/teamvks-backend.service). Backend A = vm3 `192.168.64.13:3001`, Backend B = vm4 `192.168.64.14:3002`.

| Brief item | File | What it shows |
| --- | --- | --- |
| Backend responds, `X-Backend` header | [C-manual-run-and-log.png](B-https-lb/C-manual-run-and-log.png) | first manual run: vm2 gets `200 OK` + `X-Backend: A`; vm3 logs `peer=192.168.64.12:<ephemeral port>` for each request |
| Must not bind 127.0.0.1 | [C-bind-127-refused.png](B-https-lb/C-bind-127-refused.png) | bound to loopback: `LISTEN 127.0.0.1:3001`, local curl works, vm2 gets an instant refusal (RST) |
| Installed as services | [C-services-installed.png](B-https-lb/C-services-installed.png) · [C-services-running.png](B-https-lb/C-services-running.png) | A/3001 and B/3002 from `/etc/default/teamvks-backend`, `active (running)`, `LISTEN 0.0.0.0:3001` / `:3002`, process owned by the unprivileged `teamvks-backend` user |
| Both reachable from the edge | [C-backend-a-from-edge.txt](B-https-lb/C-backend-a-from-edge.txt) · [C-backend-b-from-edge.txt](B-https-lb/C-backend-b-from-edge.txt) · [C-both-from-edge.png](B-https-lb/C-both-from-edge.png) | vm2 → `X-Backend: A` / `X-Backend: B`, JSON `{"backend": …, "status": "ok"}` |
| Service details + request log | [C-vm3-backend-a-service.txt](B-https-lb/C-vm3-backend-a-service.txt) · [C-vm4-backend-b-service.txt](B-https-lb/C-vm4-backend-b-service.txt) | `systemctl status`, listening socket, journal line for the edge's request |
| Starts at boot | [C-reboot-survives.png](B-https-lb/C-reboot-survives.png) | after `sudo reboot` of vm3: up 2 min, service active since the new boot, vm2's curl answered without manual start |

## B – Edge reverse proxy and load balancing (Task D, HTTP)

Folder: [`B-https-lb/`](B-https-lb/). Config: [configs/vm2-edge/nginx/teamvks.conf](../../configs/vm2-edge/nginx/teamvks.conf) on vm2-edge (`192.168.64.12:80`). This is the plain-HTTP stage; the HTTPS versions for form B1–B3 follow in Task E.

| Brief item | File | What it shows |
| --- | --- | --- |
| nginx installed, config valid | [D-nginx-install-and-config-test.png](B-https-lb/D-nginx-install-and-config-test.png) | nginx 1.24 active on `0.0.0.0:80` (1 master + 2 workers); `nginx -t` successful; the `upstream` and `server` blocks |
| Requests by name go through the edge | [D-first-request-lb-6x-access-log.png](B-https-lb/D-first-request-lb-6x-access-log.png) | `curl -i http://app.teamvks.test/api/status`: `Server: nginx`, `Connection: keep-alive` (hop-by-hop, added by the edge), `X-Backend` passed through |
| Repeated requests alternate | same screenshot | 6× JSON and 6× `X-Backend`: B, A, B, A, B, A |
| Round-robin inside the edge | same screenshot | access log: `upstream=` alternates `192.168.64.14:3002` / `192.168.64.13:3001`, a new client ephemeral port per request |
| Client identity behind a proxy | [D-xff-backend-view.png](B-https-lb/D-xff-backend-view.png) | backend log and page: TCP peer = edge `192.168.64.12`, `X-Forwarded-For` = client `192.168.64.14` |
| Mac and browser as clients | [D-mac-curl.png](B-https-lb/D-mac-curl.png) · [D-safari-http-backend-a.png](B-https-lb/D-safari-http-backend-a.png) · [D-safari-http-backend-b.png](B-https-lb/D-safari-http-backend-b.png) | Safari on `http://app.teamvks.test/` alternates A/B on reload; X-Forwarded-For `192.168.64.1` (the Mac) |
| Raw outputs | [D-lb-6x-http.txt](B-https-lb/D-lb-6x-http.txt) · [D-access-log.txt](B-https-lb/D-access-log.txt) · [D-backend-a-log-via-edge.txt](B-https-lb/D-backend-a-log-via-edge.txt) · [D-backend-page-via-edge.html](B-https-lb/D-backend-page-via-edge.html) | the same runs as saved text: 6 alternating responses, 12 access-log lines, backend log with `peer=192.168.64.12 xff=192.168.64.14`, backend page as served through the edge |
| One backend down (preview of D3) | [D-one-backend-down-and-restore.png](B-https-lb/D-one-backend-down-and-restore.png) | A stopped → 6× `200` from B; log line `upstream=192.168.64.13:3001, 192.168.64.14:3002 upstream_status=502, 200` (refused, retried on B in the same request); after restart A rejoins once `fail_timeout` (10 s) expires |

## B – HTTPS with a local CA (Task E · form B1, B2, B3)

Folder: [`B-https-lb/`](B-https-lb/). TLS files: [tls/](../../tls/) (CA config, extension file, the two **public** certificates). Edge config: [configs/vm2-edge/nginx/teamvks.conf](../../configs/vm2-edge/nginx/teamvks.conf).

| Form / brief item | File | What it shows |
| --- | --- | --- |
| Local CA | [E-ca-created.png](B-https-lb/E-ca-created.png) | `teamvks Lab Root CA`: subject = issuer (self-signed root), `CA:TRUE, pathlen:0`, may only sign certificates |
| Key + CSR on the edge | [E-csr-on-vm2.png](B-https-lb/E-csr-on-vm2.png) | vm2 generates its own private key; the CSR (`CN=app.teamvks.test`) self-signature verifies |
| Certificate signed | [E-cert-signed.png](B-https-lb/E-cert-signed.png) | `verify OK`, issuer = our CA, SAN `app.teamvks.test`, `api.teamvks.test`, `serverAuth`, 397 days; `git status` shows only public `.crt` files |
| TLS termination on vm2 | [E-nginx-443.png](B-https-lb/E-nginx-443.png) | key mode 600 root, `nginx -t` ok, listening on 80 and 443 (old workers still draining after the graceful reload) |
| Untrusted CA is rejected | [E-untrusted-error.png](B-https-lb/E-untrusted-error.png) | before trust: `curl: (60) SSL certificate problem: unable to get local issuer certificate` |
| Clients trust the CA | [E-trust-vms.png](B-https-lb/E-trust-vms.png) · [E-mac-curl-verified.png](B-https-lb/E-mac-curl-verified.png) | `update-ca-certificates`: `1 added` on all four VMs; Mac System keychain + Mac curl `verify ok` |
| **B1** `curl -v`, no `-k` | [E-B1-curl-v.txt](B-https-lb/E-B1-curl-v.txt) · [E-B1-curl-v.png](B-https-lb/E-B1-curl-v.png) | TLS 1.3 handshake messages, `TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS`, ALPN `h2`, SAN match, `SSL certificate verify ok`, `HTTP/2 200` |
| **B2** 6 HTTPS responses | [E-B2-lb-6x-https.txt](B-https-lb/E-B2-lb-6x-https.txt) · [E-B2-lb-6x-https.png](B-https-lb/E-B2-lb-6x-https.png) | `x-backend`: B, A, B, A, B, A |
| **B3** nginx upstream + server blocks | [E-B3-nginx-conf.txt](B-https-lb/E-B3-nginx-conf.txt) · [E-B3-nginx-conf-and-log.png](B-https-lb/E-B3-nginx-conf-and-log.png) | upstream pool, port-80 redirect server, port-443 TLS server with `proxy_pass` |
| Redirect + versions | [E-http-redirect.txt](B-https-lb/E-http-redirect.txt) · [E-redirect-versions.png](B-https-lb/E-redirect-versions.png) | `301` → `https://…`; HTTP/1.1 and HTTP/2 both `200`; TLS 1.2 also works |
| Edge log | [E-access-log-https.txt](B-https-lb/E-access-log-https.txt) | `HTTP/2.0` vs `HTTP/1.1`, `tls=TLSv1.3/TLS_AES_256_GCM_SHA384` vs `tls=TLSv1.2/ECDHE-RSA-AES256-GCM-SHA384`, redirect `301 tls=-/- upstream=-` |
| Browser | [E-safari-padlock-cert-chain.png](B-https-lb/E-safari-padlock-cert-chain.png) | Safari padlock, chain `teamvks Lab Root CA → app.teamvks.test`, "This certificate is valid" |

## D – HTTP caching and the edge cache (Task F · form D1, D2)

Folder: [`D-caching-failures/`](D-caching-failures/). Cacheable endpoint: `/api/info` ([backend/server.py](../../backend/server.py)); edge cache: `location = /api/info` in [teamvks.conf](../../configs/vm2-edge/nginx/teamvks.conf).

| Form / brief item | File | What it shows |
| --- | --- | --- |
| New backend deployed | [F-backends-redeployed.png](D-caching-failures/F-backends-redeployed.png) | both services restarted and `active` |
| Origin caching headers + 304 | [F-origin-200-304.txt](D-caching-failures/F-origin-200-304.txt) · [F-origin-200-304.png](D-caching-failures/F-origin-200-304.png) | A and B send the **same** `ETag "2f9bf8e0a1ee62ec"` and `Last-Modified`; A's ETag sent to B → `304 Not Modified` (no body); `If-Modified-Since` → `304`; `/api/status` is `no-store` |
| Edge cache enabled | [F-nginx-cache-on.png](D-caching-failures/F-nginx-cache-on.png) | `nginx -t` ok, cache directory owned by `www-data`, mode 700 |
| **D1** headers of the cached endpoint | [F-D1-headers.txt](D-caching-failures/F-D1-headers.txt) · [F-D1-headers-miss.png](D-caching-failures/F-D1-headers-miss.png) | `cache-control: public, max-age=60`, `etag`, `last-modified`, `x-cache-status: MISS` |
| Cache effect: HIT | [F-edge-hits.txt](D-caching-failures/F-edge-hits.txt) · [F-hits-then-revalidated.png](D-caching-failures/F-hits-then-revalidated.png) | 5× `HIT`, always the same `x-backend`: no backend contacted, no round-robin |
| Cache effect: 304 | [F-D1-304.txt](D-caching-failures/F-D1-304.txt) · [F-D1-304.png](D-caching-failures/F-D1-304.png) | `If-None-Match` → `HTTP/2 304` from the edge (`x-cache-status: HIT`), no body |
| Stale → revalidated | [F-hits-then-revalidated.png](D-caching-failures/F-hits-then-revalidated.png) · [F-edge-log.txt](D-caching-failures/F-edge-log.txt) · [F-edge-log.png](D-caching-failures/F-edge-log.png) | after 61 s: `REVALIDATED`; log `cache=MISS upstream=…14:3002 200` → `cache=HIT upstream=-` ×9 → `cache=REVALIDATED upstream=…13:3001 upstream_status=304` (copy fetched from B, confirmed by A: shared ETag) |
| Backends' view | [F-backend-logs.png](D-caching-failures/F-backend-logs.png) | only a handful of `/api/info` requests reached A and B; the edge's revalidation arrived at A as a `304` |
| Live data not cached | [F-status-not-cached.png](D-caching-failures/F-status-not-cached.png) | `/api/status`: `cache-control: no-store`, no `x-cache-status`, A/B still alternating |

## C – Wireshark: DNS → TCP → TLS → HTTP (Task G · form C1, C2, C3)

Folder: [`C-wireshark/`](C-wireshark/). Capture: [`phase1-dns-tcp-tls.pcapng`](C-wireshark/phase1-dns-tcp-tls.pcapng) (76 packets, SSH removed; SHA-256 `f0a8c868…a0a5`), taken on the Mac on **vm4's switch port `vmenet3`** while vm4 ran `dig`, a TLS 1.2 `curl` and a TLS 1.3 `curl`. The `.txt` files are `tshark` extracts of the same capture.

| Form item | File | What it shows |
| --- | --- | --- |
| **C1** DNS query | [G-C1-dns-query.png](C-wireshark/G-C1-dns-query.png) · [C1-dns.txt](C-wireshark/C1-dns.txt) | frame 3: `192.168.64.14:40019 → 192.168.64.11:53` UDP, ID `0x0d91`, `app.teamvks.test` type A, recursion desired |
| **C1** DNS response | [G-C1-dns-response.png](C-wireshark/G-C1-dns-response.png) | frame 4: `53 → 40019`, same ID, **authoritative**, answer `192.168.64.12`, TTL 0, answered in 1.589 ms |
| **C2** TCP handshake | [G-C2-handshake-list.png](C-wireshark/G-C2-handshake-list.png) · [G-C2-syn.png](C-wireshark/G-C2-syn.png) · [G-C2-syn-ack.png](C-wireshark/G-C2-syn-ack.png) · [C2-tcp-handshake.txt](C-wireshark/C2-tcp-handshake.txt) | frames 15–17, port `34060 → 443`: SYN raw seq 936201354 · SYN-ACK raw seq 2703154826, ack 936201355 · ACK 936201355 / 2703154827; MSS 1460, SACK, window scale ×128 |
| **C3** TLS 1.2 handshake | [G-C3-overview.png](C-wireshark/G-C3-overview.png) · [G-C3-client-hello.png](C-wireshark/G-C3-client-hello.png) · [G-C3-server-hello-certificate.png](C-wireshark/G-C3-server-hello-certificate.png) · [G-C3-certificate.png](C-wireshark/G-C3-certificate.png) · [G-C3-server-key-exchange.png](C-wireshark/G-C3-server-key-exchange.png) · [G-C3-client-key-exchange-ccs.png](C-wireshark/G-C3-client-key-exchange-ccs.png) · [C3-tls-handshake.txt](C-wireshark/C3-tls-handshake.txt) | ClientHello (SNI `app.teamvks.test`, 28 cipher suites, ALPN h2/http1.1) → ServerHello (`TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`, h2) + Certificate (`app.teamvks.test`, issuer `teamvks Lab Root CA`) + ServerKeyExchange (x25519, rsa_pss_rsae_sha256) → ClientKeyExchange + ChangeCipherSpec |
| **C3** encrypted HTTP | [G-C3-encrypted-app-data.png](C-wireshark/G-C3-encrypted-app-data.png) | Application Data records: opaque bytes, `[Application Data Protocol: HTTP2]` |
| TLS 1.3 comparison | [G-tls13-vs-tls12.png](C-wireshark/G-tls13-vs-tls12.png) | ServerHello `supported_versions: TLS 1.3`, `TLS_AES_256_GCM_SHA384`; no Certificate message visible (encrypted) |
| TLS termination | [G-edge-plaintext-backend.png](C-wireshark/G-edge-plaintext-backend.png) · [C-edge-to-backend-http.txt](C-wireshark/C-edge-to-backend-http.txt) | the same moment, edge → Backend B on port 3002: plain `GET /api/status HTTP/1.1` with `X-Forwarded-For: 192.168.64.14`, `X-Forwarded-Proto: https`, JSON reply |

Evidence for the remaining form item (D3 failure demo) is added next.
