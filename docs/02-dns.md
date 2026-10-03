# Task B: Private DNS server for `teamvks.test`

**Goal:** vm1-dns answers `app.teamvks.test` and `api.teamvks.test` with the edge's IP (`192.168.64.12`). Every VM uses it as its resolver, and the name doesn't exist anywhere on the public internet.

**Brief says:**
- create the two records;
- point at least two other machines at Mac 1;
- verify with `dig` from a client;
- always use the name, never the IP;
- be ready to explain DNS resolution versus the TCP/HTTPS connection that follows.

**Form fields:** A2 (dnsmasq config), A3 (`dig` from a client), A4 (`dig @8.8.8.8` returns NXDOMAIN)

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Resolver (client side) | the part of each VM's OS that turns a name into an IP. It reads `/etc/resolv.conf` to know which server to ask |
| DNS server | vm1 running **dnsmasq** on UDP/TCP port **53** |
| A record | name → IPv4 address: `app.teamvks.test → 192.168.64.12` |
| Forwarding | dnsmasq answers our own zone itself and passes every other name (e.g. `github.com`) to an upstream server, here the Mac (`192.168.64.1`) |
| TTL | how many seconds a client may cache an answer. dnsmasq's default for its own records is **0** (don't cache); Phase 2 changes it |
| NXDOMAIN | "this name does not exist" |
| `.test` | reserved for testing (RFC 2606) and never delegated in the public root zone, so public DNS will always say NXDOMAIN |

DNS only **finds the address**. Once the client knows `192.168.64.12`, DNS plays no further part: the next step is a TCP connection (and later TLS + HTTP) straight to that IP.

Commands are labelled with **where** to run them: a VM's SSH pane (you keep one open per VM) or the **Mac**.

## 1. Check the upstream first

dnsmasq will forward non-project names to the Mac, so make sure the Mac answers.

**vm1 pane:**

```bash
dig @192.168.64.1 github.com +short
```

You should get one or more IP addresses. If it times out, stop and tell me.

## 2. Install dnsmasq on vm1 (expect it to fail to start)

**vm1 pane:**

```bash
sudo apt install -y dnsmasq
systemctl status dnsmasq --no-pager | head -15
```

The service will most likely show **failed** with *"failed to create listening socket for port 53: Address already in use"*. Find out who already owns port 53:

```bash
sudo ss -lunp 'sport = :53'
```

You'll see `systemd-resolve` on `127.0.0.53` and `127.0.0.54`. That's Ubuntu's local resolver cache. With no config, dnsmasq tries to grab port 53 on **every** address (`0.0.0.0:53`) and collides with it. Our config fixes this with `bind-dynamic`: dnsmasq binds only its own addresses and leaves `127.0.0.53` alone.

## 3. Deploy the config

**vm1 pane:**

```bash
cd ~/cn && git pull
cat ~/cn/configs/vm1-dns/dnsmasq.d/teamvks.conf        # read every comment; you must be able to explain each line
sudo install -m 644 ~/cn/configs/vm1-dns/dnsmasq.d/teamvks.conf /etc/dnsmasq.d/teamvks.conf
sudo dnsmasq --test                                    # expect: dnsmasq: syntax check OK.
sudo systemctl restart dnsmasq
systemctl is-active dnsmasq                            # expect: active
systemctl is-enabled dnsmasq                           # expect: enabled (starts at every boot)
sudo ss -lunp 'sport = :53'
```

The last command should now show **two owners side by side**:

- `dnsmasq` on `192.168.64.11:53` (and on `127.0.0.1` / IPv6 addresses);
- `systemd-resolve` still on `127.0.0.53` / `127.0.0.54`.

## 4. Test the server before switching any client

**vm1 pane:**

```bash
dig @192.168.64.11 app.teamvks.test      # ANSWER: app.teamvks.test. 0 IN A 192.168.64.12
dig @192.168.64.11 github.com +short     # forwarded upstream: real IPs
dig @192.168.64.11 nope.teamvks.test     # status: NXDOMAIN (never forwarded, thanks to local=)
```

Then prove the server is reachable **over the LAN**.

**vm4 pane:**

```bash
dig @192.168.64.11 app.teamvks.test +short   # → 192.168.64.12
```

`@192.168.64.11` means "ask this server directly". It tests the server without touching the VM's resolver settings.

## 5. Point every VM at vm1

Two changes per VM:

1. **netplan**: the resolver becomes `192.168.64.11`. The updated files are already in `configs/*/netplan/`.
2. **`/etc/resolv.conf`**: by default Ubuntu points it at `127.0.0.53` (systemd-resolved's local cache). `dig` would then report `SERVER: 127.0.0.53`, which hides our DNS server and fails form A3. Re-pointing the symlink makes programs ask `192.168.64.11` directly. It also removes the local cache, so every lookup really goes over the wire, which you'll want in Task G.

**All four panes** (vm1 first), the same block:

```bash
cd ~/cn && git pull
sudo install -m 600 ~/cn/configs/$(hostname)/netplan/60-static.yaml /etc/netplan/60-static.yaml
sudo netplan apply
ls -l /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
ls -l /etc/resolv.conf
grep nameserver /etc/resolv.conf
```

- `$(hostname)` makes each VM pick its own folder (`configs/vm2-edge/…`).
- `netplan apply` is safe over SSH this time because the IP address doesn't change.
- The first `ls -l` shows the default (`-> ../run/systemd/resolve/stub-resolv.conf`), the second the new target.
- An "Open vSwitch" warning is harmless.

**Expected for every VM:** `/etc/resolv.conf -> /run/systemd/resolve/resolv.conf` and exactly one line, `nameserver 192.168.64.11`.

**Why the netplan files contain `accept-ra: false`.** The Mac sends IPv6 Router Advertisements on the virtual switch. They gave the VMs their `fd40:…` addresses, and they also announce the Mac (`fe80::80a9:97ff:fe14:6d64`) as a DNS server. Without this line, systemd-resolved lists that as a **second, hidden** nameserver. Normal lookups still go to vm1 first, but whenever vm1 is down the VMs would quietly fall back to the Mac. That would spoil the DNS failure demo and, in Phase 2, the backup-DNS test. The lab is IPv4-only, so ignoring the adverts costs nothing; each VM keeps its link-local `fe80::` address.

Check that the internet still works through our DNS:

**vm3 pane:**

```bash
dig github.com +short     # real IPs, via dnsmasq → Mac
sudo apt update           # no "Temporary failure resolving" errors
```

## 6. Evidence: dig from client VMs (form A3)

Each VM saves its output in `~/evidence/`; step 8 copies everything into the repo in one go.

**vm4 pane:**

```bash
mkdir -p ~/evidence
dig app.teamvks.test | tee ~/evidence/A3-dig-app-from-vm4.txt
dig api.teamvks.test | tee ~/evidence/A3-dig-api-from-vm4.txt
```

**vm2 pane:**

```bash
mkdir -p ~/evidence
dig app.teamvks.test | tee ~/evidence/A3-dig-app-from-vm2.txt
```

In each output, check:

| Line | Expect | Means |
| --- | --- | --- |
| `status:` | `NOERROR` | the name exists |
| `ANSWER SECTION` | `app.teamvks.test. 0 IN A 192.168.64.12` | name → the edge's IP, TTL 0 |
| `SERVER:` | `192.168.64.11#53(192.168.64.11) (UDP)` | our DNS server answered, on UDP port 53 |
| `Query time:` | about 1 ms | answered locally, nothing went to the internet |

That covers the brief's "at least two client machines resolve through the team DNS" (vm4 and vm2).

## 7. Evidence: public DNS doesn't know the name (form A4)

**vm4 pane:**

```bash
dig @8.8.8.8 app.teamvks.test | tee ~/evidence/A4-dig-8.8.8.8-nxdomain.txt
```

Expect `status: NXDOMAIN`. The AUTHORITY section shows the root zone's SOA (`a.root-servers.net.`): the root servers themselves say `.test` has no owner. If your network blocks outside DNS you'll get a timeout instead, which the form also accepts.

## 8. Evidence: dnsmasq config and query log (form A2)

Run this **after** steps 6–7, so the log contains those lookups.

**vm1 pane:**

```bash
mkdir -p ~/evidence
grep -Ev '^(#|$)' /etc/dnsmasq.d/teamvks.conf | tee ~/evidence/A2-dnsmasq-conf.txt
journalctl -u dnsmasq -n 40 --no-pager | tee ~/evidence/A2-dnsmasq-query-log.txt
```

**Mac** (copy all evidence into the repo):

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
for h in vm1 vm2 vm4; do scp "${h}:evidence/*" evidence/phase1/A-lan-dns/; done
```

Keep the braces in `"${h}:…"`. In zsh, `$h:e` is a modifier ("extension of `$h`"), so `"$h:evidence/*"` silently turns into `vidence/*`.

The first file is exactly what form A2 asks for: `interface=`, `listen-address=` and the `address=` lines. In the log, look for:

- `query[A] app.teamvks.test from 192.168.64.14`: vm4 asked;
- `config app.teamvks.test is 192.168.64.12`: answered from our config;
- `forwarded github.com to 192.168.64.1`: everything else goes upstream.

If `journalctl` says you lack permission, put `sudo` in front of it.

## 9. Your Mac as a client too

macOS can send just one domain to a specific DNS server: a file in `/etc/resolver/` named after the domain.

**Mac.** Run `sudo -v` **on its own first** and type your Mac password. sudo then remembers it for a few minutes. If you paste the whole block straight away, the password prompt swallows the next pasted lines as "passwords" and every `sudo` fails.

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
sudo -v
```

```bash
sudo mkdir -p /etc/resolver
sudo cp configs/mac/resolver/teamvks.test /etc/resolver/teamvks.test
scutil --dns | grep -B1 -A3 teamvks            # macOS lists a resolver for domain teamvks.test → 192.168.64.11
dscacheutil -q host -a name app.teamvks.test    # system lookup → ip_address: 192.168.64.12
ping -c 2 app.teamvks.test                      # by name, never by IP
```

`dig app.teamvks.test` on the Mac will **not** work. `dig` is a debugging tool that reads `/etc/resolv.conf` directly and ignores `/etc/resolver/`. Apps (ping, curl, Safari) use the system resolver, which honours it. On the Mac, use `dig @192.168.64.11 app.teamvks.test`.

## 10. Optional preview of Task G: DNS on the wire

1. Find vm4's switch port: `ifconfig bridge100`, Address cache, MAC `92:b1:96:9b:dc:31`.
2. In Wireshark, capture on that `vmenet` port with display filter `dns`.
3. **vm4 pane:** `dig app.teamvks.test`.

You'll see two packets:

- **Standard query** from `192.168.64.14:<random port>` to `192.168.64.11:53` (UDP);
- **Standard query response** carrying `A 192.168.64.12`, TTL 0.

Task G redoes this cleanly, together with TCP and TLS.

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `A2-dnsmasq-port53.png` | step 3: `ss -lunp` with dnsmasq on .11 and systemd-resolved on 127.0.0.53 |
| `A2-dnsmasq-conf.png` | the config on vm1 (step 8 output or `cat`) |
| `A2-dnsmasq-query-log.png` | the journal lines `query[A] … from 192.168.64.14` / `config … is 192.168.64.12` |
| `A3-dig-from-vm4.png` | `dig app.teamvks.test` on vm4: SERVER .11, ANSWER .12 |
| `A3-resolv-conf.png` | step 5 loop output: all four VMs on `nameserver 192.168.64.11` |
| `A4-dig-8.8.8.8-nxdomain.png` | `dig @8.8.8.8` with `status: NXDOMAIN` |
| `B-mac-resolver.png` | step 9 on the Mac: `scutil --dns`, `dscacheutil`, `ping app.teamvks.test` |

## Explain it back (viva practice: answer in your own words)

1. Walk through `curl https://app.teamvks.test`: which part is DNS (which IP, port, protocol) and which part is the connection that follows?
2. Why does `dig @8.8.8.8 app.teamvks.test` return NXDOMAIN, and why is that a *good* result?
3. What does `local=/teamvks.test/` prevent? What would happen without it for `nope.teamvks.test`?
4. Why must `listen-address` not be `127.0.0.1` only?
5. Why did dnsmasq fail right after install, and what is listening on `127.0.0.53`?
6. Why is the TTL `0`? What changes for clients when it becomes 30 seconds (Phase 2)?
7. Why does `dig` on the Mac fail while `ping app.teamvks.test` works?
8. DNS used UDP here. When does DNS switch to TCP?
9. Which cloud service plays the role of vm1? (Hint: Route 53 private hosted zone.)
10. If vm1 is switched off, what still works and what breaks? (This is failure demo 1.)
11. Where did the extra `nameserver fe80::…` come from, and why would it have spoiled the DNS failure demo?

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `apt install` ends with a dpkg error about dnsmasq | it couldn't start (step 2). Deploy the config (step 3), then `sudo dpkg --configure -a` |
| dnsmasq still "Address already in use" after step 3 | config not in `/etc/dnsmasq.d/`, or `bind-dynamic` missing: `sudo dnsmasq --test`, `sudo ss -lunp 'sport = :53'` |
| `dig` on a VM shows `SERVER: 127.0.0.53` | the resolv.conf symlink from step 5 wasn't made on that VM |
| Mac: `sudo: 3 incorrect password attempts`, then `No such file or directory` | a pasted block fed its own lines to the password prompt: run `sudo -v` alone first (step 9) |
| `cp: vidence/*: No such file or directory` on the Mac | zsh read `$h:e` as a modifier: write `"${h}:evidence/*"` |
| `/etc/resolv.conf` lists a second `nameserver fe80::…` | the VM still accepts the Mac's IPv6 router adverts: reinstall the repo's netplan file (it has `accept-ra: false`) and `sudo netplan apply` |
| `dig` from vm4 times out | dnsmasq down or not on 192.168.64.11: `systemctl status dnsmasq`, `ss -lunp` on vm1 |
| `apt update` fails on VMs after step 5 | forwarding broken: `dig @192.168.64.11 github.com` on vm1; check `server=192.168.64.1` |
| `status: NXDOMAIN` for `app.teamvks.test` from our server | typo in an `address=` line: compare with the repo file, `sudo dnsmasq --test`, restart |
| Mac `ping app.teamvks.test` fails | file name must be exactly `teamvks.test`; a VPN (Tailscale/NetBird) can override DNS: quit it; check `scutil --dns` |
