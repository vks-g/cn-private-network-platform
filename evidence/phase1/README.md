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

Evidence for the remaining form sections is added as each task is built: B1–B3 (HTTPS, reverse proxy, load balancing), C (Wireshark) and D (caching, failure demo).
