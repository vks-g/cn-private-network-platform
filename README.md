# CN Private Network Service Platform

Computer Networks course project, Section D. The whole network runs locally on one Mac: four Ubuntu virtual machines in UTM take the four Mac roles from the project brief.

A client types `https://app.teamvks.test`. The name is resolved by our own DNS server, the HTTPS connection ends at an nginx edge, and nginx hands the request to one of two backend servers. Every step is captured in Wireshark.

> The application stays simple. The network is the project.

## Team

| Name | Enrollment No. | Work mode |
| --- | --- | --- |
| `<your name>` | `<enrollment number>` | Solo |

Submission type: **Type 3 – Virtual machines (UTM on Apple Silicon)**

## Phase 1 progress

| Task | What | Status |
| --- | --- | --- |
| A | Private LAN between 4 VMs | ☐ |
| B | Private DNS (dnsmasq) for `teamvks.test` | ☐ |
| C | Two REST backends (A on 3001, B on 3002) | ☐ |
| D | nginx reverse proxy + round-robin load balancer | ☐ |
| E | HTTPS with a local certificate authority | ☐ |
| F | HTTP caching (Cache-Control, ETag, 304) | ☐ |
| G | Wireshark evidence for DNS → TCP → TLS → HTTP | ☐ |
| 6.3 | Failure demonstrations | ☐ |

## Lab inventory

| VM | Role in brief | Hostname | IP | Service |
| --- | --- | --- | --- | --- |
| VM1 | Mac 1: DNS server + test client | `vm1-dns` | 192.168.64.11 | dnsmasq, 53/UDP+TCP |
| VM2 | Mac 2: edge proxy + load balancer | `vm2-edge` | 192.168.64.12 | nginx, 80 → 443/TCP |
| VM3 | Mac 3: Backend A | `vm3-backend-a` | 192.168.64.13 | Python REST, 3001/TCP |
| VM4 | Mac 4: Backend B + test client | `vm4-backend-b` | 192.168.64.14 | Python REST, 3002/TCP |
| Host | UTM host, Wireshark, browser client | macOS | 192.168.64.1 | gateway of the UTM shared network |

## Repository layout

```text
.
├── README.md
├── docs/            architecture + one step-by-step guide per task
├── configs/         config files for each VM (netplan, dnsmasq, nginx)
├── backend/         Python backend source + systemd unit
├── tls/             public CA / server certificates and the OpenSSL extension file
└── evidence/phase1/ screenshots, terminal output and packet captures, by form section
```

