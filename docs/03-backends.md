# Task C: Two backend services

**Goal:** vm3 runs Backend A on port 3001 and vm4 runs Backend B on port 3002. Both answer `GET /` and `GET /api/status` and tag every response with `X-Backend: A` or `X-Backend: B`. Both are reachable from the edge (vm2) over the LAN.

**Brief says:**
- keep the code minimal;
- listen on a LAN-accessible interface, **not 127.0.0.1**;
- use fixed ports 3001 / 3002.

**Form fields:** none directly. Task C feeds **B2** (the `X-Backend` header proves load balancing) and the README's "how to run the backends" (required by the form).

Commands are labelled with **where** to run them: a VM's SSH pane or the **Mac**.

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Socket | one end of a connection: **IP + port + protocol**. The backend opens a *listening* TCP socket on port 3001 |
| Bind address | which local IP the listening socket accepts connections on. `0.0.0.0` = every interface; `127.0.0.1` = this VM only |
| Ephemeral port | the random high port the *client* picks for its side of a connection (e.g. `41822`) |
| HTTP request | `GET /api/status HTTP/1.1` + headers (+ optional body) |
| HTTP response | status line `HTTP/1.1 200 OK` + headers (`Content-Type`, `Content-Length`, `X-Backend`) + body |
| REST / JSON | a URL per resource, answered with machine-readable JSON |
| systemd service | the OS starts the program at boot, restarts it on crashes and collects its log |

## 1. Get the code (vm3 pane and vm4 pane)

```bash
cd ~/cn && git pull
ls backend
less ~/cn/backend/server.py        # q to quit
```

`server.py` is about 120 lines. Find these parts; you'll be asked about them:

- `respond()`: picks the status, content type and body for each path, then sends the status line, headers and body;
- `send_header("X-Backend", …)`: the header that later proves load balancing;
- `home_page()`: shows the TCP peer (`client_address`) next to `X-Forwarded-For`;
- `log_message()`: prints one line per request;
- `--host` defaults to `0.0.0.0`.

## 2. Run Backend A by hand and call it from the edge

**vm3 pane:** start it in the foreground so you can watch requests arrive.

```bash
python3 ~/cn/backend/server.py --id A --port 3001
```

It prints `Backend A listening on 0.0.0.0:3001` and waits.

**vm2 pane:**

```bash
curl -i http://192.168.64.13:3001/api/status
curl -s http://192.168.64.13:3001/
```

**Expect:** `HTTP/1.1 200 OK`, `Content-Type: application/json`, **`X-Backend: A`**, and the JSON body. The second command prints the HTML page; its "TCP connection from" row shows `192.168.64.12`, i.e. vm2.

**Look back at the vm3 pane.** Each request logged a line like:

```text
backend=A peer=192.168.64.12:41822 xff=- "GET /api/status HTTP/1.1" 200 -
```

`41822` is vm2's **ephemeral port**: vm2's kernel picked it for this connection, and the backend's side is the fixed port 3001. `xff=-` means no proxy was involved (yet).

Stop the server in the vm3 pane with **Ctrl+C**.

## 3. Experiment: why not 127.0.0.1?

**vm3 pane:** start it bound to loopback only, in the background (`&`), and look at the socket:

```bash
python3 ~/cn/backend/server.py --id A --port 3001 --host 127.0.0.1 &
ss -ltn 'sport = :3001'
curl -s http://127.0.0.1:3001/api/status
```

`ss` shows `LISTEN … 127.0.0.1:3001`, and the local `curl` works.

**vm2 pane:**

```bash
curl -i http://192.168.64.13:3001/api/status
```

**Expect:** `Failed to connect … Connection refused`. Nothing listens on `192.168.64.13:3001`, so vm3's kernel answers vm2's SYN with a **RST**. The host is reachable (ping works); only the port is closed. That's an instant "refused", not a timeout.

**vm3 pane:** stop the background server.

```bash
kill %1
```

## 4. Install both backends as services

**vm3 pane and vm4 pane**, the same block. `$(hostname)` picks A/3001 on vm3 and B/3002 on vm4:

```bash
sudo install -D -m 644 ~/cn/backend/server.py /opt/teamvks/backend/server.py
sudo install -m 644 ~/cn/backend/teamvks-backend.service /etc/systemd/system/teamvks-backend.service
sudo install -m 644 ~/cn/configs/$(hostname)/teamvks-backend.env /etc/default/teamvks-backend
cat /etc/default/teamvks-backend
sudo systemctl daemon-reload
sudo systemctl enable --now teamvks-backend
systemctl status teamvks-backend --no-pager | head -12
sudo ss -ltnp '( sport = :3001 or sport = :3002 )'
```

| Line | What it does |
| --- | --- |
| `install -D …/opt/teamvks/backend/` | copies the program to a system location (`-D` creates the folders) |
| `teamvks-backend.service` | the unit: `ExecStart` runs `server.py --id ${BACKEND_ID} --port ${BACKEND_PORT}` |
| `/etc/default/teamvks-backend` | this VM's values: `A`/`3001` or `B`/`3002` |
| `daemon-reload` | makes systemd read the new unit file |
| `enable --now` | start now **and** at every boot |

**Expect:**

- `Active: active (running)` and the log line `Backend A listening on 0.0.0.0:3001` (B / 3002 on vm4);
- `ss` shows `LISTEN … 0.0.0.0:3001` owned by `python3`.

Read the unit file (`cat /etc/systemd/system/teamvks-backend.service`). `DynamicUser=yes` runs the backend as a throwaway unprivileged user: ports above 1024 don't need root, so it shouldn't have root.

## 5. Test both backends from the edge and save the evidence

**vm2 pane:**

```bash
mkdir -p ~/evidence
curl -si http://192.168.64.13:3001/api/status | tee ~/evidence/C-backend-a-from-edge.txt
curl -si http://192.168.64.14:3002/api/status | tee ~/evidence/C-backend-b-from-edge.txt
```

**Expect:** two `200 OK` responses, one with `X-Backend: A` and `"backend": "A"`, the other with `X-Backend: B` and `"backend": "B"`.

**vm3 pane and vm4 pane:**

```bash
mkdir -p ~/evidence
{ systemctl status teamvks-backend --no-pager | head -12
  sudo ss -ltnp '( sport = :3001 or sport = :3002 )'
  journalctl -u teamvks-backend -n 10 --no-pager; } | tee ~/evidence/C-$(hostname)-service.txt
```

The journal lines show `peer=192.168.64.12:<ephemeral port>`: the edge's request from the previous step.

**Mac** (copy into the repo):

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
mkdir -p evidence/phase1/B-https-lb
for h in vm2 vm3 vm4; do scp "${h}:evidence/C-*" evidence/phase1/B-https-lb/; done
```

## 6. Prove it survives a reboot

**vm3 pane:** `sudo reboot`, then wait about 30 seconds.

**vm2 pane:**

```bash
curl -s http://192.168.64.13:3001/api/status
```

It answers again without you starting anything, which shows `enable` worked. Reconnect the vm3 pane with `ssh vm3`. This matters for the live checkpoint: after a Mac restart, starting the VMs is all you need to do.

## What's still missing (on purpose)

Right now **anything on the LAN** can call the backends directly. Try it on the **Mac**: `curl -s http://192.168.64.13:3001/api/status`. In Task D clients will only ever use the edge, and Phase 2 (Extension C) adds firewall rules so that only vm2 can reach ports 3001/3002.

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `C-manual-run-and-log.png` | step 2: vm2's `curl -i` + the request log line in the vm3 pane |
| `C-bind-127-refused.png` | step 3: `ss` showing `127.0.0.1:3001` + "Connection refused" from vm2 |
| `C-services-running.png` | step 4: `active (running)` + `ss` `0.0.0.0:3001` / `:3002` on vm3 and vm4 |
| `C-both-from-edge.png` | step 5: vm2 gets `X-Backend: A` and `X-Backend: B` |

## Explain it back (viva practice: answer in your own words)

1. What is a socket? Which four values identify the TCP connection from vm2 to Backend A?
2. Why must the backend bind `0.0.0.0` and not `127.0.0.1`? Why did vm2 get "refused" rather than a timeout?
3. In `peer=192.168.64.12:41822`, what is `41822` and who chose it?
4. Why doesn't the backend need root, and why is that safer?
5. What will the `X-Backend` header let us prove in Task D?
6. What's the difference between `curl -i` and `curl -I`?
7. Why must an HTTP/1.1 response carry `Content-Length` (or chunked encoding) when the connection stays open?
8. After Task D, the "TCP connection from" row will show `192.168.64.12` even when vm4 asks. Why?

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `OSError: [Errno 98] Address already in use` | another copy is still running on that port: Ctrl+C the foreground one, or `kill %1` |
| vm2 gets `Connection refused` after step 4 | service not running, or bound to 127.0.0.1: `systemctl status teamvks-backend`, `sudo ss -ltnp` |
| `Failed to load environment files` in the status | `/etc/default/teamvks-backend` missing: redo the `install … teamvks-backend.env` line (needs `git pull` first) |
| `can't open file '/opt/teamvks/backend/server.py'` | the first `install -D` line was skipped |
| `X-Backend` shows the wrong letter | the wrong `.env` file was installed: `cat /etc/default/teamvks-backend`, fix, `sudo systemctl restart teamvks-backend` |
