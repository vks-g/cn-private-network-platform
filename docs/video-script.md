# Phase 1 video: shot list

**Limits (form):** ≤ 5 minutes · ≤ 500 MB · `.mp4`, 1080p recommended · Google Drive, "Anyone with the link can view" · file name `CN_Phase1_[Section][TeamName][InfraType].mp4` → **`CN_Phase1_DteamvksType3.mp4`**. The form also asks for the **D3 failure demo inside the video**.

Talking points are bullets, not a script: say them in your own words.

## Before you press record (10 min)

1. All four VMs running in UTM; Ghostty 2×2 split with `ssh vm1` … `ssh vm4`; font bigger (Cmd +); run `clear` in every pane.
2. Turn on **Do Not Disturb**; close unrelated windows and tabs.
3. **Fresh edge cache**, so the MISS → HIT shot works. vm2 pane:
   ```bash
   sudo rm -rf /var/cache/nginx-teamvks/* && sudo systemctl reload nginx
   ```
4. **Wireshark ready.** Mac: `ifconfig bridge100 | sed -n '/Address cache/,$p'` → note vm4's port (MAC `92:b1:96:9b:dc:31`). In Wireshark: Capture → Options → that `vmenetN` → capture filter `not port 22`. Don't start yet.
5. Browser tabs ready: GitHub repo README (architecture diagram), and `https://app.teamvks.test/` in Safari.
6. Keep this file open on your phone or a second screen to read the commands from.

Recording: **Cmd+Shift+5 → Record Entire Screen → Options → Microphone: MacBook Pro Microphone → Record**. Stop from the menu-bar ■. It's fine to record in 2–3 parts and join them in iMovie.

## Shots

### 0:00–0:20 · Intro
**Show:** GitHub README → architecture diagram.
- Name, enrollment 2401020094, solo project, Type 3: four Ubuntu VMs in UTM on one Mac.
- vm1 DNS, vm2 nginx edge, vm3 Backend A, vm4 Backend B + client; private subnet 192.168.64.0/24.

### 0:20–0:40 · The LAN
**Show:** UTM window with 4 VMs running, then the 2×2 panes. **All panes:**
```bash
hostname; ip -br addr show enp0s1
```
- Four machines, four static IPs .11–.14 on one switch.

### 0:40–1:15 · Private DNS
**vm1:**
```bash
grep -Ev '^(#|$)' /etc/dnsmasq.d/teamvks.conf
```
**vm4:**
```bash
dig app.teamvks.test
dig @8.8.8.8 app.teamvks.test | grep status
```
- Point at `SERVER: 192.168.64.11` and `ANSWER … 192.168.64.12` (the edge, never a backend).
- Public DNS says NXDOMAIN: the name only exists in our network.

### 1:15–2:05 · HTTPS + load balancing
**vm2:**
```bash
grep -Ev '^\s*(#|$)' /etc/nginx/sites-available/teamvks | sed -n '/^upstream/,$p'
```
**vm4:**
```bash
curl -v https://app.teamvks.test 2>&1 | grep -E 'Connected|SSL connection|subject:|issuer:|subjectAltName|verify ok|HTTP/2 200|x-backend'
for i in 1 2 3 4 5 6; do curl -s https://app.teamvks.test/api/status; echo; done
```
**Safari:** reload `https://app.teamvks.test/` → click the padlock (chain: teamvks Lab Root CA → app.teamvks.test).
- Upstream block = the pool, round-robin; TLS ends at nginx with a certificate from my own CA; no `-k`.
- A/B alternate; the client only ever talks to the edge.

### 2:05–2:35 · Caching
**vm4:**
```bash
curl -sI https://app.teamvks.test/api/info | grep -iE 'cache-control|etag|x-backend|x-cache'
curl -sI https://app.teamvks.test/api/info | grep -iE 'x-backend|x-cache'
```
- `max-age=60` + ETag; first MISS (fetched from a backend), then HIT (the edge answered by itself).

### 2:35–3:45 · Live Wireshark
**Wireshark:** Start capture. **vm4:**
```bash
dig app.teamvks.test; curl -s --tls-max 1.2 https://app.teamvks.test/api/status
```
**Wireshark:** stop ■, then apply these filters one after another:
1. `dns`: query .14 → .11 UDP 53; response A 192.168.64.12, TTL 0.
2. `tcp.flags.syn == 1 && tcp.port == 443`: SYN, SYN-ACK (then the ACK): handshake before any data.
3. `tls`: Client Hello (SNI) → Server Hello, **Certificate** → Change Cipher Spec → Application Data.
- HTTP is inside Application Data, so headers and JSON are unreadable: TLS encrypts them.

### 3:45–4:40 · Failure demo (D3, Option A)
**vm4 (before):**
```bash
for i in 1 2 3 4 5 6; do curl -s https://app.teamvks.test/api/status; echo; done
```
**vm3:**
```bash
sudo systemctl stop teamvks-backend; systemctl is-active teamvks-backend
```
**vm4 (during):**
```bash
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%{http_code} ' https://app.teamvks.test/api/status; curl -s https://app.teamvks.test/api/status; echo; done
```
- All 200, all B: the application layer on vm3 failed; DNS, TCP to the edge and TLS were fine, so nginx retried on B.

**vm3:**
```bash
sudo systemctl start teamvks-backend; systemctl is-active teamvks-backend
```
**vm4 (after, wait ~10 s):**
```bash
sleep 10; for i in 1 2 3 4 5 6; do curl -s https://app.teamvks.test/api/status; echo; done
```
- A is back after nginx's 10-second fail_timeout.

### 4:40–5:00 · Wrap-up
**Show:** GitHub repo: README progress table, `configs/`, `backend/`, `evidence/phase1/`.
- Everything (configs, code, captures, evidence) is in the repo. End.

## After recording (Mac)

Join and trim in iMovie if needed (File → Share → File, 1080p). Then convert and check:

```bash
cd ~/Movies   # or wherever the recording is
ffmpeg -i "Screen Recording.mov" -vf "scale=-2:1080" -c:v libx264 -crf 26 -preset medium -c:a aac -b:a 128k CN_Phase1_DteamvksType3.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 CN_Phase1_DteamvksType3.mp4   # must be ≤ 300
ls -lh CN_Phase1_DteamvksType3.mp4                                                        # must be ≤ 500M
```

Upload to Google Drive → Share → **General access: Anyone with the link · Viewer** → copy link → open it in a **private/incognito window** to test. Don't put the video in the repo (`.gitignore` blocks `*.mp4`, `*.mov`).
