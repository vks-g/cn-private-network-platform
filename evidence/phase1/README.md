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

Evidence for the remaining form sections is added as each task is built: A2–A4 (DNS), B (HTTPS, reverse proxy, load balancing), C (Wireshark) and D (caching, failure demo).
