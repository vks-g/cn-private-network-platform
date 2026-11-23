# Phase 2 – evidence

The 19 screenshots that prove each Phase 2 extension, in the order they were run on 23 Nov 2026. Each screenshot is a real terminal session on the VMs: the pane header names the machine and its IP. [`raw/`](raw/) holds the same output as plain text, one file per screenshot. Results and explanations are in the [Phase 2 report](../../docs/phase2-report.md).

| # | Shows | Extension · brief bullet |
| --- | --- | --- |
| 01 | [Backup dnsmasq on vm3 answers the same records as vm1, TTL 30](01-dns-backup-server-on-vm3.png) | A · second resolver with the same records |
| 02 | [vm4 and the Mac list `.11` first and `.13` second](02-dns-clients-list-both-servers.png) | A · clients list both servers |
| 03 | [dnsmasq stopped on vm1 → ICMP unreachable → query retried on `.13`, HTTPS still 200](03-dns-failover-primary-down.png) | A · primary stopped, clients keep resolving |
| 04 | [Both DNS down → "Could not resolve host" (ping and HTTPS by IP work) vs both backends down → 502](04-dns-failure-vs-app-failure.png) | A · DNS failure vs application failure |
| 05 | [nftables rule on vm3/vm4 + rollback copy saved first](05-isolation-rule-and-rollback-copy.png) | C · restrict 3001/3002 to the edge, rollback copy |
| 06 | [Before: 200 from anywhere. After: vm1 and the Mac time out, the edge gets 200, HTTPS still alternates; drop counters](06-isolation-before-after.png) | C · edge reaches backends, client cannot |
| 07 | [Rollback: table deleted, ruleset identical to the copy, direct access back](07-isolation-rollback.png) | C · restore the original configuration |
| 08 | [Backend A stopped → 10/10 `200` from B; access log shows the retry `502, 200`; error.log](08-ha-backend-a-down.png) | D · all requests served by B |
| 09 | [Backend A restarted → A/B alternate again after `fail_timeout`](09-ha-backend-a-recovered.png) | D · load balancing resumes |
| 10 | [nginx stopped on vm2 → DNS and both backends fine, service down](10-ha-edge-is-spof.png) | D · the edge is the single point of failure |
| 11 | [Standby edge on vm3: own key + CSR, signed by our CA, same nginx file, `X-Edge: vm3-backend-a`](11-standby-edge-on-vm3.png) | E · standby nginx with the same configuration |
| 12 | [Record moved to `.13`: vm1 switches at once, vm4 keeps the cached `.12` until the 30 s TTL runs out](12-cutover-ttl-countdown.png) | B + E · cached answer until TTL expiry, cutover |
| 13 | [Access logs: the old edge served vm4 until its TTL ran out, the new edge got vm1 at once and vm4 afterwards](13-cutover-access-logs.png) | E · cached clients hit the old edge, new lookups the standby |
| 14 | [Cutback: server says `.12`, vm4's cache still `.13` → `resolvectl flush-caches` switches it at once](14-cutback-flush-cache.png) | B · manual cache flush |
| 15 | [Drill: record name typo → `diagnose.sh` stops at DNS (NXDOMAIN) → diff → fixed](15-drill-dns-record-typo.png) | F · DNS layer |
| 16 | [Drill: nginx stopped → TCP refused while ping works → fixed](16-drill-tcp-nginx-stopped.png) | F · TCP layer |
| 17 | [Drill: self-signed certificate → TLS verify fails → diff → fixed](17-drill-tls-self-signed.png) | F · TLS layer |
| 18 | [Drill: upstream ports mistyped → 502, error.log names the bad ports → fixed](18-drill-http-upstream-port.png) | F · application layer |
| 19 | [Final state: all four layers pass from vm4 and vm1, configs match the repo, no firewall table left](19-final-state-all-layers-pass.png) | final state for the evaluation |
