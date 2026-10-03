# Task D: Edge reverse proxy and load balancer

**Goal:** nginx on vm2 is the **single entry point**. Clients ask for `app.teamvks.test`, DNS sends them to vm2, and nginx forwards each request to Backend A or Backend B in turn.

**Brief says:**
- clients never connect to the backends directly;
- use round-robin (or another strategy you can explain);
- show that repeated requests alternate between A and B;
- explain why the client never needs the backend IPs.

**Form fields:** B2 (6 responses showing both `X-Backend: A` and `B`) and B3 (nginx upstream + server block). This task builds both over plain HTTP; Task E switches them to HTTPS, and the final form answers come from that HTTPS version.

Commands are labelled with **where** to run them: a VM's SSH pane or the **Mac**.

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Reverse proxy | a server that receives the client's request and makes its **own** request to a backend on the client's behalf. The client only ever talks to the proxy |
| Upstream | nginx's name for the pool of backends: `192.168.64.13:3001` and `192.168.64.14:3002` |
| Round-robin | take the backends in turn: A, B, A, B, … (nginx's default) |
| Passive health check | nginx notices a backend is broken when a real request to it fails, then skips it for `fail_timeout` (open-source nginx has no active probing) |
| `X-Forwarded-For` | header the proxy adds so the backend still learns the original client's IP |
| Two TCP connections | client → edge (port 80) and edge → backend (port 3001/3002) are **separate** connections, each with its own handshake |

Cloud equivalent: vm2 is an **AWS Application Load Balancer**, and the upstream block is its **target group**.

## 1. Install nginx (vm2 pane)

```bash
sudo apt install -y nginx
systemctl is-active nginx
sudo ss -ltnp 'sport = :80'
curl -sI http://127.0.0.1 | head -3
```

**Expect:**
- `active`;
- `LISTEN … 0.0.0.0:80` owned by `nginx`;
- `HTTP/1.1 200 OK` + `Server: nginx/1.24.0 (Ubuntu)`: that's nginx's default "Welcome" site.

## 2. Read and deploy our config (vm2 pane)

```bash
cd ~/cn && git pull
cat ~/cn/configs/vm2-edge/nginx/teamvks.conf
sudo install -m 644 ~/cn/configs/vm2-edge/nginx/teamvks.conf /etc/nginx/sites-available/teamvks
sudo ln -sf /etc/nginx/sites-available/teamvks /etc/nginx/sites-enabled/teamvks
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

| Line | What it does |
| --- | --- |
| `sites-available/` + link in `sites-enabled/` | Ubuntu's layout: `nginx.conf` only loads what's linked in `sites-enabled` |
| `rm … sites-enabled/default` | turns off the Welcome site, so ours is the only site on port 80 |
| `nginx -t` | checks the syntax **before** applying. Expect `syntax is ok` and `test is successful` |
| `reload` | applies the new config without dropping connections in progress |

Read the config before going on. You'll be asked to explain:

- the `upstream` block: both backends, and `zone` (one shared round-robin counter for all nginx worker processes);
- `max_fails`/`fail_timeout`: the passive health check;
- `proxy_pass`: forwards to the pool;
- the `proxy_set_header` lines: `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`;
- `proxy_next_upstream`: retry on the other backend if one fails.

## 3. First request by name (vm4 pane)

```bash
curl -i http://app.teamvks.test/api/status
```

**Expect:** `HTTP/1.1 200 OK`, then `Server: nginx/1.24.0 (Ubuntu)`, **`X-Backend: A`** (or B), and the JSON body.

What just happened:

1. **DNS:** vm4 asked vm1 for `app.teamvks.test` and got `192.168.64.12`.
2. **Client → edge:** TCP to vm2 port 80, then the HTTP request.
3. **Edge → backend:** nginx picked a backend and opened a **second** TCP connection to it (port 3001 or 3002).
4. **Back to the client:** the response came back through nginx.

The `Server:` header now says **nginx**, because the edge rewrites it. `X-Backend` passed through untouched, so you can still tell who did the work.

## 4. Load balancing: 6 requests (vm4 pane)

```bash
mkdir -p ~/evidence
for i in 1 2 3 4 5 6; do curl -s http://app.teamvks.test/api/status; done | tee ~/evidence/D-lb-6x-http.txt
for i in 1 2 3 4 5 6; do curl -si http://app.teamvks.test/api/status | grep -i '^x-backend'; done
```

**Expect:** the backends alternate: `"backend": "A"`, `"B"`, `"A"`, `"B"`, … The starting letter doesn't matter. The second loop shows the same thing using only the `X-Backend` header, which is exactly what form B2 asks for (over HTTPS, after Task E).

## 5. The edge's view: access log (vm2 pane)

```bash
mkdir -p ~/evidence
tail -n 12 /var/log/nginx/teamvks-access.log | tee ~/evidence/D-access-log.txt
```

Each line looks like:

```text
192.168.64.14:51234 "GET /api/status HTTP/1.1" 200 upstream=192.168.64.13:3001 upstream_status=200 upstream_time=0.002
```

- The client side is vm4 with an **ephemeral port**.
- `upstream=` alternates between `192.168.64.13:3001` and `192.168.64.14:3002`. That's round-robin, seen from the inside.

## 6. The backend's view: who really connected? (vm4 pane, then vm3 pane)

**vm4 pane:**

```bash
curl -s http://app.teamvks.test/ | tee ~/evidence/D-backend-page-via-edge.html
```

Look at the HTML table: **"TCP connection from 192.168.64.12"** (the edge) and **"Original client (X-Forwarded-For) 192.168.64.14"** (you). Run it again if it came from B; both backends show the same thing.

**vm3 pane:**

```bash
journalctl -u teamvks-backend -n 5 --no-pager | tee ~/evidence/D-backend-a-log-via-edge.txt
```

**Expect:** lines with `peer=192.168.64.12:<port> xff=192.168.64.14`. The backend's TCP peer is the edge, never the client. The client's identity only survives because nginx wrote it into a header.

## 7. Your Mac and Safari (Mac)

```bash
curl -s http://app.teamvks.test/api/status
```

Then open **Safari** at `http://app.teamvks.test/` and press **Cmd+R** a few times. The heading switches between "Backend A" and "Backend B", and X-Forwarded-For shows `192.168.64.1` (your Mac on the UTM network).

It's still `http://`, so Safari shows "Not Secure". Task E fixes that.

## 8. Preview: one backend down (optional, a taste of failure demo D3)

**vm3 pane:**

```bash
sudo systemctl stop teamvks-backend
```

**vm4 pane:**

```bash
for i in 1 2 3 4 5 6; do curl -s http://app.teamvks.test/api/status; done
```

**Expect:** six `200` responses, **all from B**. In the vm2 log (`tail -n 6 /var/log/nginx/teamvks-access.log`), one line shows `upstream=192.168.64.13:3001, 192.168.64.14:3002`: nginx tried A, got refused, and retried on B in the same request. After that it skips A for 10 s (`fail_timeout`), then tries it again.

**vm3 pane:** restore it.

```bash
sudo systemctl start teamvks-backend
```

The full failure demos, with evidence, come after Task G.

## 9. Copy the evidence into the repo (Mac)

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
for h in vm2 vm3 vm4; do scp "${h}:evidence/D-*" evidence/phase1/B-https-lb/; done
```

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `D-nginx-installed.png` | step 1: nginx active, listening on :80 |
| `D-nginx-config-test.png` | step 2: `nginx -t` successful |
| `D-first-request.png` | step 3: `curl -i` by name: `Server: nginx`, `X-Backend` |
| `D-lb-6x.png` | step 4: both loops alternating A/B |
| `D-access-log.png` | step 5: `upstream=` alternating .13:3001 / .14:3002 |
| `D-xff-backend-view.png` | step 6: TCP peer .12 vs X-Forwarded-For .14 |
| `D-safari-http.png` | step 7: Safari on `http://app.teamvks.test/` |
| `D-one-backend-down.png` | step 8 (optional): all B + the retry line in the log |

## Explain it back (viva practice: answer in your own words)

1. Why does the client never need to know the backend IP addresses? What would change for clients if we added a Backend C?
2. How many TCP connections does one `curl http://app.teamvks.test/api/status` create, and between which IP:port pairs?
3. The backend sees `peer=192.168.64.12`. How does it still learn the real client's IP?
4. Why does `Server:` say nginx while `X-Backend:` still says A or B?
5. What is round-robin? Name another strategy (e.g. `least_conn`, `ip_hash`) and when you'd use it.
6. What does `max_fails=1 fail_timeout=10s` do? Why is it called a *passive* health check?
7. What does `proxy_next_upstream` change for the client when a backend is down?
8. Which AWS service does vm2 play the role of? What is still a single point of failure here?

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `nginx -t` fails | typo or missing `;`: the message names the file and line. Compare with the repo file |
| `curl` by name returns the "Welcome to nginx!" page | our site isn't linked, or `default` is still enabled: `ls -l /etc/nginx/sites-enabled/` |
| `502 Bad Gateway` | nginx can't reach either backend: from vm2 `curl -i http://192.168.64.13:3001/api/status`; read `sudo tail /var/log/nginx/error.log` |
| Always the same backend | both backends must be running; for browser tests use Cmd+R; check `upstream=` in the access log |
| `Could not resolve host: app.teamvks.test` | DNS (Task B): `grep nameserver /etc/resolv.conf`, `systemctl status dnsmasq` on vm1 |
| `Permission denied` reading the access log | your user isn't in the `adm` group: use `sudo tail …` |
