# Phase 1 video script

**Target:** 4:40–4:55, never over 5:00 · ≤ 500 MB · 1080p `.mp4` · file name **`CN_Phase1_DteamvksType3.mp4`** (form pattern `CN_Phase1_[Section][TeamName][InfraType].mp4`) · Google Drive, "Anyone with the link: Viewer". The form requires the **D3 failure demo inside the video**.

**Style:** one thing on screen at a time, a short sentence before each command, one sentence on what the result proves. Talk continuously and cut every typing or waiting pause in iMovie. Paste commands from this file instead of typing them.

Read only the **Say** lines aloud (in your own words if you prefer). Everything else is the operator checklist.

## Screen layout

| Window | Used for |
| --- | --- |
| **Safari** tab 1: `docs/showcase.html` (open the file from Finder) | intro + architecture |
| **Safari** tab 2: `https://app.teamvks.test/` | padlock shot |
| **Safari** tab 3: `https://github.com/vks-g/cn-private-network-platform` | outro |
| **UTM** main window | the four VMs |
| **Ghostty window 1**: 2×2 split, `ssh vm1` … `ssh vm4` | everything that runs on a VM |
| **Ghostty window 2**: one Mac shell, full screen | the Mac as the client (HTTPS, caching, Wireshark, failure demo) |
| **Wireshark** | live capture |

Zoom the fonts up (Cmd + in Ghostty, twice). In a 2×2 split, **Cmd+Shift+Enter** zooms the focused pane to full window and back. Use it for long outputs like the nginx config.

## Before recording (10 min)

1. Start all four VMs. Then check the services. **vm1:** `systemctl is-active dnsmasq` · **vm2:** `systemctl is-active nginx` · **vm3 and vm4:** `systemctl is-active teamvks-backend`. All must say `active`.
2. **Empty the edge cache**, so the caching shot shows MISS first. **vm2:**
   ```bash
   sudo sh -c 'rm -rf /var/cache/nginx-teamvks/*' && sudo systemctl restart nginx
   ```
3. **Wireshark:** Capture → Options → select **bridge100** → capture filter `not port 22` (must turn green) → **don't press Start yet**. Close the window with the filter kept.
4. Clear every pane: `clear`. Turn on **Do Not Disturb**. Hide the Dock if you like.
5. **Don't show the terminal running Claude Code anywhere in the video.**
6. Recording: **Cmd+Shift+5 → Record Entire Screen → Options → Microphone: MacBook Pro Microphone**. Record the six clips below separately, then join them in iMovie.

---

## Clip 1 · 0:00–0:35 · Introduction and architecture

**Show:** UTM main window with `vm1-dns`, `vm2-edge`, `vm3-backend-a`, `vm4-backend-b` running.

**Say:**
> "Hi, I'm Gokul VKS, enrollment 2401020094. I did this Computer Networks Phase 1 project individually. Instead of four physical Macs I'm using four Ubuntu Server virtual machines in UTM on my MacBook. That's submission Type 3. Each VM is a separate computer on one private network: a DNS server, an nginx edge, Backend A and Backend B."

**Show:** Safari tab 1 (showcase page): the architecture diagram, then scroll to the machine table.

**Say:**
> "Here's the request flow. A client first asks my DNS server on vm1 for app.teamvks.test and gets the edge's address. It then connects over HTTPS to nginx on vm2. nginx ends the TLS connection and forwards each request to Backend A or Backend B in turn. All four machines are on 192.168.64.0/24, and my Mac is the gateway."

## Clip 2 · 0:35–1:30 · The configurations

**Say:** "Let's look at the DNS configuration."

**vm1:**
```bash
grep -Ev '^(#|$)' /etc/dnsmasq.d/teamvks.conf
```
Point at `listen-address=192.168.64.11`, `local=/teamvks.test/` and both `address=` lines.

**Say:**
> "dnsmasq listens on 192.168.64.11. It answers app and api.teamvks.test with the edge's address, 192.168.64.12, and forwards every other name to my Mac."

**Say:** "Next, the backend."

**vm3:**
```bash
grep -nE 'if path ==|elif path ==|"X-Backend"|"Cache-Control"|"ETag"|0\.0\.0\.0"' /opt/teamvks/backend/server.py
grep BACKEND /etc/default/teamvks-backend
```
**vm4:**
```bash
grep BACKEND /etc/default/teamvks-backend
```

**Say:**
> "Both backends run the same small Python program. It serves slash, /api/status and /api/info, adds an X-Backend header to every response and listens on 0.0.0.0, so the edge can reach it. Only the settings differ: vm3 is A on port 3001, vm4 is B on port 3002."

**Say:** "Now nginx."

**vm2:** zoom the pane first (Cmd+Shift+Enter).
```bash
grep -Ev '^\s*(#|$)' /etc/nginx/sites-available/teamvks | sed -n '/^upstream/,$p'
```
Point at the `upstream` block (both backends), `listen 443 ssl http2`, the two certificate lines, `proxy_pass`, and `return 301` on port 80. Unzoom.

**Say:**
> "The upstream block lists Backend A and Backend B. With no other method set, nginx uses round robin. It accepts HTTPS on port 443 with my certificate, sends every request to the upstream group with proxy_pass, and port 80 only redirects to HTTPS."

## Clip 3 · 1:30–2:05 · DNS from the clients, then the backends from the edge

**Say:** "Let's check that the machines use my DNS server."

**vm2, vm3 and vm4** (same command in each):
```bash
grep nameserver /etc/resolv.conf; dig app.teamvks.test | grep -E 'status|^app|SERVER'
```
**vm4:**
```bash
dig @8.8.8.8 app.teamvks.test | grep status
```

**Say:**
> "The edge and both backends use 192.168.64.11 as their resolver, and it answers app.teamvks.test with 192.168.64.12. Asking Google's public DNS gives NXDOMAIN: the name only exists in my private network."

**Say:** "Now both backends, straight from the edge."

**vm2:**
```bash
curl -si http://192.168.64.13:3001/api/status; echo; curl -si http://192.168.64.14:3002/api/status
```

**Say:**
> "Both return 200, one with X-Backend A and one with X-Backend B. So the edge can reach both backends over the private network."

## Clip 4 · 2:05–3:10 · HTTPS, load balancing and caching (Mac as the client)

**Say:** "Now HTTPS, from my Mac."

**Mac (Ghostty window 2):**
```bash
curl -v https://app.teamvks.test
```
Point at `subjectAltName … matched`, `issuer: CN=teamvks Lab Root CA`, `SSL certificate verify ok`, `HTTP/2 200`, `x-backend`.

**Say:**
> "I made my own small certificate authority and signed a certificate for app.teamvks.test with it. The CA is trusted on my Mac and on the VMs, so curl verifies the certificate without the insecure -k option. The name matches, the connection is TLS 1.3 with HTTP/2, and nginx returns 200."

**Safari tab 2:** reload `https://app.teamvks.test/`, click the **padlock** → Show Certificate → the chain `teamvks Lab Root CA → app.teamvks.test`.

**Say:** "Safari trusts it too: padlock, and the chain goes up to my CA."

**Say:** "Now load balancing."

**Mac:**
```bash
for i in {1..6}; do curl -s https://app.teamvks.test/api/status; done
```

**Say:**
> "Six requests, and the answers alternate between A and B. The client only ever talks to the edge and never needs the backend addresses."

**Say:** "Finally, caching."

**Mac:**
```bash
curl -sI https://app.teamvks.test/api/info
curl -sI -H 'If-None-Match: "2f9bf8e0a1ee62ec"' https://app.teamvks.test/api/info
```

**Say:**
> "The /api/info endpoint says cache-control public, max-age 60, and it carries an ETag. The first request is a MISS: the edge fetched it from a backend. When I ask again with that ETag I get 304 Not Modified with no body: my copy is still valid, and the edge answered by itself."

## Clip 5 · 3:10–4:10 · Live Wireshark capture

**Say:** "Now let's capture a fresh DNS lookup and HTTPS connection in Wireshark."

**Mac:**
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
route -n get 192.168.64.12 | grep interface
```

**Say:** "I cleared the Mac's DNS cache. Traffic to my lab goes out on bridge100, the Mac's port on the UTM virtual switch."

**Wireshark:** Start the capture on **bridge100** (filter `not port 22` already set). **Mac:**
```bash
dig @192.168.64.11 app.teamvks.test
curl -s --tlsv1.2 --tls-max 1.2 https://app.teamvks.test/api/status
```
**Wireshark:** Stop (■).

1. Filter `dns && ip.addr == 192.168.64.11` → double-click the **response** → expand Answers.

   **Say:** "My Mac, 192.168.64.1, asks 192.168.64.11 on UDP port 53. The answer is app.teamvks.test, A record 192.168.64.12, TTL 0."

2. Filter `tcp.flags.syn == 1 && tcp.port == 443` → right-click the **SYN** → Conversation Filter → TCP.

   **Say:** "The Mac sends SYN from a random port to port 443, nginx replies SYN-ACK, and the Mac sends ACK. Now there's a reliable, ordered TCP connection, before any data."

3. Add `&& tls` to the filter (`tcp.stream eq N && tls`).

   **Say:** "Then TLS: Client Hello with the server name, Server Hello with the chosen cipher and the Certificate, Change Cipher Spec, and from then on only Application Data. The HTTP request and the JSON are inside those encrypted records, so Wireshark can't read them."

## Clip 6 · 4:10–4:55 · Failure demo (D3, Option A) and outro

**Say:** "Now the failure demo. Right now both A and B answer."

**Mac:**
```bash
for i in {1..6}; do curl -s https://app.teamvks.test/api/status; done
```
**vm3:**
```bash
sudo systemctl stop teamvks-backend; systemctl is-active teamvks-backend
```
**Mac:**
```bash
for i in {1..6}; do curl -s -o /dev/null -w '%{http_code} ' https://app.teamvks.test/api/status; curl -s https://app.teamvks.test/api/status; done
```

**Say:**
> "Backend A is inactive, but every request still returns 200, all from B. The failure is at the application layer on vm3: DNS, the TCP connection to the edge and TLS all still work, so nginx just retries on Backend B."

**vm3:**
```bash
sudo systemctl start teamvks-backend; systemctl is-active teamvks-backend
```
**Mac:**
```bash
sleep 10; for i in {1..6}; do curl -s https://app.teamvks.test/api/status; done
```

**Say:** "A is active again, and after nginx's ten-second wait both backends are back in the rotation."

**Safari tab 3:** the GitHub repo: README (team, progress table, how to run the backends), then the `configs`, `backend` and `evidence/phase1` folders.

**Say:**
> "Everything's in my GitHub repository: the configuration files, the backend code, the packet capture and all the evidence. That completes my Phase 1 demonstration. Thank you."

---

## After recording

1. **iMovie:** New Project → drag the six clips in order → cut every pause where you're typing or waiting (select → Cmd+B to split → delete). Watch the total time at the top; it must be **under 5:00**.
2. **Export:** File → Share → File → Resolution 1080p, Quality High → save as `CN_Phase1_DteamvksType3`.
3. **Check it (Mac)**, from the folder you saved it in:
   ```bash
   ffprobe -v error -show_entries format=duration -of csv=p=0 CN_Phase1_DteamvksType3.mp4   # must be < 300
   ls -lh CN_Phase1_DteamvksType3.mp4                                                        # must be < 500M
   ```
   If iMovie gave you a `.mov`, or the file is too big, convert it:
   ```bash
   ffmpeg -i CN_Phase1_DteamvksType3.mov -vf scale=-2:1080 -c:v libx264 -crf 26 -preset medium -c:a aac -b:a 128k CN_Phase1_DteamvksType3.mp4
   ```
4. **Drive:** upload → Share → General access: **Anyone with the link · Viewer** → Copy link → open it in a **private window** to check that it plays.
5. Never commit the video to the repo (`.gitignore` blocks `*.mp4` and `*.mov`).
