# Task A: Build the private LAN in UTM

**Goal:** four Ubuntu VMs on one private subnet, each with a fixed IP, all able to ping each other.

**Brief says:** connect all machines to one LAN; record IP, mask, gateway, interface and MAC; ping every pair; draw the topology.

**Form fields:** A1 (machine IPs and roles), A5 (ping between all pairs)

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Subnet `192.168.64.0/24` | the first 24 bits are the network part, so 192.168.64.1–254 are on the same LAN |
| Interface | the VM's virtual network card, `enp0s1` |
| MAC address | layer-2 address of that card, used on the virtual switch |
| Default gateway | where packets go when the destination is **not** in our subnet. Here that's the Mac, `192.168.64.1`, which NATs to the internet |
| UTM Shared Network | a virtual switch on the Mac (`bridge100`, with one `vmenet` port per VM). All VMs plug into it, so they are on the same LAN |

VM↔VM traffic never touches the gateway. Same subnet means the VMs find each other with ARP and talk directly through the switch.

## 0. Before you start

- Download **Ubuntu Server 24.04.x LTS for ARM64**. At the time of writing the current file is `ubuntu-24.04.5-live-server-arm64.iso` from <https://cdimage.ubuntu.com/releases/24.04/release/>. Use 24.04, not 26.04: these guides are written against it.
- Disk: about 15 GB free is enough for everything.

## 1. Create the base VM (it becomes `vm1-dns`)

In UTM:

1. **+** → **Virtualize** → **Linux**.
2. Leave **Use Apple Virtualization** unchecked (we want the QEMU backend). Under Boot ISO Image, choose **Browse** and pick the ISO.
3. Hardware: **2048 MB** memory, **2** CPU cores. The installer needs the extra RAM; we drop to 1 GB later.
4. Storage: **10 GB**.
5. Shared directory: skip.
6. Name: **`vm1-dns`** → Save.
7. Right-click the VM → **Edit** → **Network**: check that Network Mode is **Shared Network** → Save.

## 2. Install Ubuntu Server

Start the VM and go through the installer. Use the defaults except for these:

| Screen | Choice |
| --- | --- |
| Type of install | **Ubuntu Server** (not "minimized") |
| Network | leave DHCP on `enp0s1`. Note the address it gets (192.168.64.x) |
| Storage | Use an entire disk, **uncheck "Set up this disk as an LVM group"** (otherwise Ubuntu leaves part of the 10 GB unused) |
| Profile | Server name **`vm1-dns`**, username **`vks`**, a password you'll reuse on all VMs |
| Ubuntu Pro | Skip |
| SSH | **✓ Install OpenSSH server** |
| Snaps | none |

When it says **Reboot Now**, click it. If it asks you to remove the installation medium, eject the ISO (the disc icon in the VM window toolbar, or Edit → Drives → clear the CD/DVD), then press Enter.

## 3. First boot: update, tools, project repo

Log in on the UTM console:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y dnsutils curl tcpdump net-tools traceroute git
git clone https://github.com/vks-g/cn-private-network-platform.git ~/cn
ip -br link            # note the interface name: expected enp0s1
ip -br addr            # note the DHCP address
```

From the Mac, check that SSH works: `ssh vks@<that DHCP address>`. Then on the VM run `sudo poweroff`.

Why install everything now? The three clones inherit it, so you install once instead of four times. Package roles (dnsmasq, nginx) come later, on the right VM only.

If the interface isn't `enp0s1`, replace `enp0s1` in every file under `configs/*/netplan/` before going on.

## 4. Clone it three times

In UTM, for each of `vm2-edge`, `vm3-backend-a` and `vm4-backend-b`:

1. Right-click `vm1-dns` → **Clone**.
2. Right-click the clone → **Edit**:
   - **Information**: set the name (e.g. `vm2-edge`).
   - **Network** → MAC Address → **Random**. This is essential.
   - **System**: set memory to **1024 MB**.
3. Save.

Set `vm1-dns` itself to 1024 MB too.

Why the new MAC? Two cards with the same MAC on one switch confuse it, and frames go to the wrong VM. You'll prove the four MACs are different in step 8.

## 5. Give each clone its own identity

The clones are perfect copies: same hostname, same `machine-id` (the DHCP client ID is derived from it) and same SSH host keys. **Boot the clones one at a time** and run this on the UTM console. Change `NEW` for each clone:

```bash
NEW=vm2-edge                                   # vm3-backend-a, vm4-backend-b for the others
sudo hostnamectl set-hostname "$NEW"
sudo sed -i "s/vm1-dns/$NEW/" /etc/hosts       # the 127.0.1.1 line
sudo rm /etc/machine-id && sudo systemd-machine-id-setup
sudo rm /etc/ssh/ssh_host_* && sudo dpkg-reconfigure openssh-server
```

`vm1-dns` keeps its original identity, so skip this step for it.

## 6. Fixed IP addresses (all four VMs)

A server needs an address that never changes: clients and configs point at it. DHCP could hand out a different one after a reboot.

Do this **on the UTM console**, not over SSH. Changing the IP drops an SSH session. Example for vm2-edge; use your VM's folder name:

```bash
cat ~/cn/configs/vm2-edge/netplan/60-static.yaml          # read it first: every line is commented
ls /etc/netplan/                                          # usually 50-cloud-init.yaml (the DHCP config)
sudo mv /etc/netplan/50-cloud-init.yaml ~/50-cloud-init.yaml.bak
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo install -m 600 ~/cn/configs/vm2-edge/netplan/60-static.yaml /etc/netplan/60-static.yaml
sudo netplan try                                          # press ENTER within 120 s to keep it
ip -br addr show enp0s1                                   # should show 192.168.64.12/24
ip route                                                  # default via 192.168.64.1
sudo reboot
```

- The `99-disable-network-config` line stops cloud-init from rewriting the network config at boot.
- `netplan try` rolls back automatically if you lose access. That's why we use it instead of `netplan apply`.

When all four are done, start all four VMs together.

**Shortcut once you've done one VM by hand:** `scripts/personalize-vm.sh` runs steps 5 and 6 for you. It skips the identity part automatically when the hostname already matches (so on `vm1-dns` it only sets the IP), and it still uses `netplan try`. Run it on the UTM console:

```bash
cd ~/cn && git pull && sudo bash scripts/personalize-vm.sh vm3-backend-a
sudo reboot
```

## 7. SSH shortcuts on the Mac

From here on, work from Mac Terminal: copy/paste works and screenshots are clean.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/cn_lab -C cn-lab          # just press Enter at the passphrase prompt
cat configs/common/ssh-config-snippet >> ~/.ssh/config    # run from the repo folder on the Mac
for h in vm1 vm2 vm3 vm4; do ssh-copy-id -i ~/.ssh/cn_lab.pub $h; done
ssh vm1 hostname                                          # → vm1-dns, no password
```

Tip: open four Terminal tabs (or a 2×2 split) with `ssh vm1` … `ssh vm4`. Rename the tabs. The video uses this layout.

## 8. Record the inventory (form A1)

Run from the repo folder on the Mac:

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform   # tee writes relative paths: start in the repo
mkdir -p evidence/phase1/A-lan-dns
for h in vm1 vm2 vm3 vm4; do
  echo "===== $h"
  ssh $h 'hostname; ip -br addr show enp0s1; ip -br link show enp0s1; ip route show default'
done | tee evidence/phase1/A-lan-dns/A1-inventory.txt
```

Each block gives you:

- the hostname
- the IP/prefix (`ip -br addr`)
- the MAC (`ip -br link`)
- the gateway (`default via …`)

Copy the four MACs into the inventory table in `docs/architecture.md`.

## 9. Ping every pair (form A5)

There are 6 pairs among 4 VMs. They must be **VM→VM**; host→VM doesn't count.

```bash
{
ssh vm1 'hostname; ping -c 4 192.168.64.12'
ssh vm1 'hostname; ping -c 4 192.168.64.13'
ssh vm1 'hostname; ping -c 4 192.168.64.14'
ssh vm2 'hostname; ping -c 4 192.168.64.13'
ssh vm2 'hostname; ping -c 4 192.168.64.14'
ssh vm3 'hostname; ping -c 4 192.168.64.14'
} | tee evidence/phase1/A-lan-dns/A5-ping-matrix.txt
```

Then look at layer 2: `ssh vm1 ip neigh | tee evidence/phase1/A-lan-dns/A5-arp-table-vm1.txt`. vm1 has now learned the MAC of every VM it pinged, through ARP.

## 10. Find the right capture point (saves pain in Task G)

UTM's Shared Network is a **switch**, and the Mac has two kinds of interface on it:

| Interface on the Mac | What it is | What Wireshark sees there |
| --- | --- | --- |
| `bridge100` | the Mac's **own** port on the switch | broadcasts (e.g. ARP who-has) + traffic to or from the Mac only |
| `vmenet0` … `vmenet3` | **one port per VM** (the VM's "cable") | everything that VM sends or receives |

A switch forwards a unicast frame only out of the destination's port, so VM↔VM traffic never reaches `bridge100`. That's the reason you can't sniff other people's traffic on a switched LAN; an old hub copied every frame to every port.

1. Map ports to VMs: `ifconfig bridge100` → the **Address cache** lines read `<MAC> Vlan1 vmenetX`. Match the MACs with `A1-inventory.txt`. The numbers follow VM start order, so check again after restarting VMs.
2. Wireshark → capture on **vm2's `vmenet` port** → display filter `arp || icmp`.
3. Flush vm2's ARP cache so ARP has to run again, then ping vm3:
   ```bash
   ssh -t vm2 'sudo ip neigh flush dev enp0s1 && ping -c 3 192.168.64.13'
   ```
4. Expect the ARP request (broadcast), vm3's ARP reply "is at 7a:14:…" (unicast), then 3 ICMP echo request/reply pairs. Expand one ICMP packet: Ethernet II → IPv4 → ICMP.

Try step 3 again while capturing on `bridge100`: only the broadcast ARP request shows up. That screenshot is the proof that the virtual network behaves like a switch.

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `A1-utm-network-vm1..4.png` | each VM's Network settings in UTM: Shared Network + its own MAC |
| `A1-four-vms-terminal.png` | the 2×2 terminal split, each pane showing `hostname; ip -br addr` |
| `A1-inventory-terminal.png` | the step 8 inventory output |
| `A5-ping-matrix.png` | the ping matrix output (0% packet loss on all six) |
| `A5-arp-table-vm1.png` | vm1's ARP cache after the pings |
| `A-bridge100-switch-table.png` | `ifconfig bridge100`: member ports + MAC address table |
| `A-wireshark-bridge100-broadcast-only.png` | step 10 on `bridge100`: only the broadcast ARP request |
| `A-wireshark-vmenet0-arp-icmp.png` | step 10 on vm2's port: full ARP + ICMP exchange, one packet expanded |

Cmd+Shift+4, then Space, captures one window. Cmd+Shift+5 → Options → Save to lets you pick `_inbox` once.

## Explain it back (viva practice: answer in your own words)

1. Why can vm1 reach vm2 without going through 192.168.64.1?
2. What does `/24` mean, and how many hosts fit in this subnet?
3. Which layer does a MAC address belong to, and which an IP address? Where does each show up in `ip neigh`?
4. `ping` has no port number. Why? Which protocol does it use?
5. What would break if two clones kept the same MAC address?
6. Which real-world thing does UTM's Shared Network stand for in the brief's 4-Mac setup?
7. Why does a capture on `bridge100` show the ARP *request* between two VMs but not the *reply*?

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Two VMs get the same DHCP address | MAC not randomized, or machine-id not reset (step 4/5) |
| `netplan try` warns "permissions too open" | file must be mode 600: use `sudo install -m 600 …` as shown |
| Static IP lost after reboot | cloud-init file not disabled, or `50-cloud-init.yaml` still in `/etc/netplan/` |
| `ssh vm1` asks for a password | `ssh-copy-id` not done for that VM |
| SSH warns "REMOTE HOST IDENTIFICATION HAS CHANGED" | old key in known_hosts: `ssh-keygen -R 192.168.64.1X` |
| No `bridge100` on the Mac | no VM is running in Shared Network mode |
| Wireshark shows no packets between two VMs | you are capturing on `bridge100`; capture on the VM's `vmenet` port (step 10) |
| `tee: … No such file or directory` | you ran it outside the repo folder: `cd` into the repo first |
