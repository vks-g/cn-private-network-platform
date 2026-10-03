# CN Private Network Service Platform

Computer Networks course project, Section D. The whole network runs locally on one Mac: four Ubuntu virtual machines in UTM take the four Mac roles from the project brief.

A client types `https://app.teamvks.test`. The name is resolved by our own DNS server, the HTTPS connection ends at an nginx edge, and nginx hands the request to one of two backend servers. Every step is captured in Wireshark.

> The application stays simple. The network is the project.

## Team

| Name | Enrollment No. | Work mode |
| --- | --- | --- |
| Gokul VKS | 2401020094 | Solo |

Submission type: **Type 3 – Virtual machines (UTM on Apple Silicon)**

## Phase 1 progress

| Task | What | Status |
| --- | --- | --- |
| A | Private LAN between 4 VMs | ✅ [evidence](evidence/phase1/README.md#a--private-lan-task-a--form-a1-a5) |
| B | Private DNS (dnsmasq) for `teamvks.test` | ✅ [evidence](evidence/phase1/README.md#a--private-dns-task-b--form-a2-a3-a4) |
| C | Two REST backends (A on 3001, B on 3002) | ✅ [evidence](evidence/phase1/README.md#b--backend-services-task-c) |
| D | nginx reverse proxy + round-robin load balancer | ✅ [evidence](evidence/phase1/README.md#b--edge-reverse-proxy-and-load-balancing-task-d-http) |
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

The full topology, request flow, protocol layer map and cloud equivalents are in [docs/architecture.md](docs/architecture.md).

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

All Phase 1 evidence is indexed in [evidence/phase1/README.md](evidence/phase1/README.md), and the text for the submission form is in [evidence/phase1/form-answers.md](evidence/phase1/form-answers.md).


## How to run the backends

Backend A runs on `vm3-backend-a` (`192.168.64.13:3001`) and Backend B on `vm4-backend-b` (`192.168.64.14:3002`). Both run the same Python program, [backend/server.py](backend/server.py), which needs only the standard library.

```bash
# quick manual run (Ctrl+C to stop)
python3 backend/server.py --id A --port 3001      # on vm3
python3 backend/server.py --id B --port 3002      # on vm4

# as a systemd service (what the lab uses), on each backend VM
sudo install -D -m 644 ~/cn/backend/server.py /opt/teamvks/backend/server.py
sudo install -m 644 ~/cn/backend/teamvks-backend.service /etc/systemd/system/
sudo install -m 644 ~/cn/configs/$(hostname)/teamvks-backend.env /etc/default/teamvks-backend
sudo systemctl daemon-reload && sudo systemctl enable --now teamvks-backend

# check from the edge (vm2)
curl -i http://192.168.64.13:3001/api/status      # X-Backend: A
curl -i http://192.168.64.14:3002/api/status      # X-Backend: B
```

Endpoints: `GET /` (HTML status page), `GET /api/status` (`{"backend": "A", "status": "ok", ...}`). Every response carries `X-Backend: A|B`. Details: [backend/README.md](backend/README.md).

## Guides

Each guide covers the concept, the commands, the expected output, the screenshots to take and viva practice questions.

1. [UTM lab setup – private LAN (Task A)](docs/01-utm-lab-setup.md)
2. [Private DNS with dnsmasq (Task B)](docs/02-dns.md)
3. [Two REST backends (Task C)](docs/03-backends.md)
4. [Edge reverse proxy and load balancer (Task D)](docs/04-edge-load-balancer.md)
5. [HTTPS with our own certificate authority (Task E)](docs/05-tls.md)

More guides are added as each task is built.
