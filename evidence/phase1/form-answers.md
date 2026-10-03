# Phase 1 form answers

Text to paste into the Google Form, taken from the real output in this folder. The form asks for actual terminal output, so where a box has room, paste the raw `.txt` file instead of the summary.

## General

| Field | Answer |
| --- | --- |
| Team name / number | `teamvks` (solo) |
| Submission type | Type 3 – Virtual machines (UTM) |
| GitHub repository URL | https://github.com/vks-g/cn-private-network-platform |
| Recording Drive link | _after the video is recorded_ |
| Student names and enrollment numbers | `<enrollment number> <your name>` |

## A1 – Machine IPs and roles

```text
Type 3: four Ubuntu Server 24.04 (ARM64) VMs in UTM on one Apple Silicon Mac.
UTM Shared Network 192.168.64.0/24, gateway/NAT = host Mac 192.168.64.1 (bridge100).

VM1 vm1-dns       / DNS server + test client           : 192.168.64.11/24 (enp0s1, MAC ce:6c:90:a5:66:5a)
VM2 vm2-edge      / Edge nginx + load balancer         : 192.168.64.12/24 (enp0s1, MAC 6a:9b:d7:70:ed:9d)
VM3 vm3-backend-a / Backend A, port 3001               : 192.168.64.13/24 (enp0s1, MAC 7a:14:d5:23:b0:70)
VM4 vm4-backend-b / Backend B, port 3002 + test client : 192.168.64.14/24 (enp0s1, MAC 92:b1:96:9b:dc:31)
Host Mac          / UTM host, Wireshark                : 192.168.64.1/24 (bridge100)
```

Source: [A-lan-dns/A1-inventory.txt](A-lan-dns/A1-inventory.txt)

## A5 – Ping between all machine pairs (VM → VM)

```text
vm1-dns       → vm2-edge      : ping 192.168.64.12 — 4 packets, 0% loss, avg 0.946 ms
vm1-dns       → vm3-backend-a : ping 192.168.64.13 — 4 packets, 0% loss, avg 1.147 ms
vm1-dns       → vm4-backend-b : ping 192.168.64.14 — 4 packets, 0% loss, avg 1.197 ms
vm2-edge      → vm3-backend-a : ping 192.168.64.13 — 4 packets, 0% loss, avg 1.463 ms
vm2-edge      → vm4-backend-b : ping 192.168.64.14 — 4 packets, 0% loss, avg 1.167 ms
vm3-backend-a → vm4-backend-b : ping 192.168.64.14 — 4 packets, 0% loss, avg 1.225 ms
All replies ttl=64: same layer-2 segment, no router hop.
```

Source: [A-lan-dns/A5-ping-matrix.txt](A-lan-dns/A5-ping-matrix.txt)

## A2, A3, A4 · B · C · D

_Filled in as each task is completed._
