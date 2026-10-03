# Task F: HTTP caching

**Goal:** one endpoint, `/api/info`, is cacheable. It is fresh for 60 seconds, carries an `ETag` and `Last-Modified`, and answers `304 Not Modified` when the client's copy is still current. Live data (`/` and `/api/status`) is never cached. On top of that, the edge (vm2) keeps its own copy of `/api/info` and answers repeat requests itself, which is exactly what a CDN edge does.

**Brief says:**
- add caching headers (`Cache-Control`, `ETag` or `Last-Modified`) on at least one endpoint;
- show a cache effect: a `304`, or a response served from cache;
- explain what is cached, where, and for how long.

**Form fields:** D1 (response headers of the cached endpoint), D2 (explain `max-age`, `ETag` and `304` in your own words)

Commands are labelled with **where** to run them: a VM's SSH pane or the **Mac**.

## Concepts to understand first

| Term | Meaning here |
| --- | --- |
| `Cache-Control: max-age=60` | the response stays **fresh** for 60 s: any cache may reuse it without asking the server |
| `public` | shared caches (like our edge) may store it, not only the browser |
| `no-store` | never keep a copy: used for `/api/status`, because it must show the live backend every time |
| `ETag` | a **validator**: a fingerprint of the content (`"2f9bf8e0a1ee62ec"`). Same content → same ETag |
| `Last-Modified` | a date validator: when the content last changed |
| Conditional request | after the copy goes **stale**, the client asks "still `If-None-Match: "<etag>"`?" instead of downloading it again |
| `304 Not Modified` | "yes, your copy is still valid": headers only, **no body** |
| Edge cache | nginx stores the backend's response and answers repeats itself: `X-Cache-Status: MISS` (fetched), `HIT` (from the edge's copy), `REVALIDATED` (copy was stale, backend confirmed it with a 304) |

**Why the ETag is identical on A and B:** the body of `/api/info` is the same on both backends, and the ETag is a hash of the body. With round-robin, the request that revalidates may land on the *other* backend; if the ETags differed, every revalidation there would be a full `200` and the cache would be useless.

## 1. Deploy the new backend (vm3 pane and vm4 pane)

```bash
cd ~/cn && git pull
sudo install -m 644 ~/cn/backend/server.py /opt/teamvks/backend/server.py
sudo systemctl restart teamvks-backend
systemctl is-active teamvks-backend
```

Read what changed: `git log -p -1 -- backend/server.py`, or `less ~/cn/backend/server.py` and look for `INFO_ETAG`, `cache_headers` and `not_modified()`.

## 2. The origin's behaviour, without any edge cache (vm2 pane)

Talk to the backends directly, so you see what the **backend** itself does.

```bash
mkdir -p ~/evidence
{
curl -si http://192.168.64.13:3001/api/info; echo
curl -sI http://192.168.64.14:3002/api/info
ETAG=$(curl -sI http://192.168.64.13:3001/api/info | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
echo "ETag from A: $ETAG"
curl -si -H "If-None-Match: $ETAG" http://192.168.64.14:3002/api/info
curl -sI -H 'If-Modified-Since: Sat, 03 Oct 2026 18:00:00 GMT' http://192.168.64.13:3001/api/info | head -1
curl -sI http://192.168.64.13:3001/api/status | grep -i '^cache-control'
} | tee ~/evidence/F-origin-200-304.txt
```

**Expect:**

1. A: `200 OK`, `Cache-Control: public, max-age=60`, `ETag: "…"`, `Last-Modified: …`, `X-Backend: A`, and the JSON body.
2. B: the **same** `ETag` and `Last-Modified`, but `X-Backend: B`.
3. The ETag **taken from A** sent to **B** → `HTTP/1.1 304 Not Modified`, with no `Content-Length` and no body.
4. `If-Modified-Since` with the same date → `304`.
5. `/api/status` → `Cache-Control: no-store`.

## 3. Turn on the edge cache (vm2 pane)

```bash
cd ~/cn && git pull
sudo install -m 644 ~/cn/configs/vm2-edge/nginx/teamvks.conf /etc/nginx/sites-available/teamvks
sudo nginx -t
sudo systemctl reload nginx
sudo ls -ld /var/cache/nginx-teamvks
```

What's new in the config:

- `proxy_cache_path`: where the copies live and how much space they may use;
- `location = /api/info`: `proxy_cache`, `proxy_cache_revalidate on`, and an `X-Cache-Status` header;
- the proxy settings moved up to the `server` block so both locations share them;
- the log line gains `cache=$upstream_cache_status`.

**Expect:** `nginx -t` successful, and a `/var/cache/nginx-teamvks` directory owned by `www-data` (the nginx workers' user).

## 4. Form D1: headers of the cached endpoint (vm4 pane)

```bash
mkdir -p ~/evidence
curl -sI https://app.teamvks.test/api/info | tee ~/evidence/F-D1-headers.txt
for i in 1 2 3 4 5; do curl -sI https://app.teamvks.test/api/info | grep -iE '^x-backend|^x-cache-status' | paste -sd' ' -; done | tee ~/evidence/F-edge-hits.txt
```

**Expect:**

- First: `HTTP/2 200`, `cache-control: public, max-age=60`, `etag`, `last-modified`, `x-backend: A` (or B), **`x-cache-status: MISS`**: the edge had no copy, so it fetched one.
- Then five lines, all **`HIT`** and all with the **same** `x-backend`. The edge answered from its copy and no backend was contacted, so round-robin doesn't even happen.

## 5. A 304 through the edge (vm4 pane)

```bash
ETAG=$(curl -sI https://app.teamvks.test/api/info | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '\r')
echo "$ETAG"
curl -si -H "If-None-Match: $ETAG" https://app.teamvks.test/api/info | tee ~/evidence/F-D1-304.txt
```

**Expect:** `HTTP/2 304` with `etag` and `x-cache-status: HIT`, and **no body**. The edge compared your ETag with its cached copy and answered by itself.

## 6. Let it go stale (vm4 pane, then vm2 pane)

**vm4 pane** (waits a little over a minute):

```bash
sleep 61; curl -sI https://app.teamvks.test/api/info | grep -iE '^x-backend|^x-cache-status'
```

**Expect:** `x-cache-status: REVALIDATED`. The copy was older than `max-age=60`, so the edge asked a backend `If-None-Match: "<etag>"`, the backend said `304`, and the copy became fresh again **without re-downloading the body**.

**vm2 pane:**

```bash
tail -n 12 /var/log/nginx/teamvks-access.log | tee ~/evidence/F-edge-log.txt
```

**Expect:**

- `cache=MISS upstream=192.168.64.1x:300x upstream_status=200`: fetched;
- `cache=HIT upstream=-`: answered by the edge, no backend involved;
- `cache=REVALIDATED … upstream_status=304`: the backend's 304 refreshed the copy.

**vm3 pane and vm4 pane** (see it from the backends):

```bash
journalctl -u teamvks-backend -n 20 --no-pager | grep '/api/info'
```

Only a handful of `/api/info` requests reached the backends, even though you sent many more, and one of them ended in `304`.

## 7. Live data is never cached (vm4 pane)

```bash
curl -sI https://app.teamvks.test/api/status | grep -iE '^cache-control|^x-cache|^x-backend'
for i in 1 2 3 4; do curl -s https://app.teamvks.test/api/status; done
```

**Expect:** `cache-control: no-store`, **no** `x-cache-status` header (that location has no cache), and A/B still alternating.

## 8. In the browser (Mac, optional)

1. Safari → Settings → Advanced → tick **Show features for web developers**.
2. Open `https://app.teamvks.test/api/info`, then Develop → **Show Web Inspector** → **Network**.
3. Reload (Cmd+R). The request shows status **304** or is served from the **memory/disk cache**. Click it to see `Cache-Control`, `ETag` and `X-Cache-Status` in the response headers.

## 9. Copy the evidence into the repo (Mac)

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
mkdir -p evidence/phase1/D-caching-failures
for h in vm2 vm4; do scp "${h}:evidence/F-*" evidence/phase1/D-caching-failures/; done
```

## Form D2: write it in your own words

The form asks for 2–4 sentences on `max-age`, `ETag` and `304`. Don't copy this guide; explain what **you** saw:

- what `max-age=60` allowed the edge to do for 60 s (step 4);
- what the ETag is and why A and B share it (step 2);
- what the 304 saved, and what it didn't save (it still costs a round trip) (steps 5–6).

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `F-origin-200-304.png` | step 2: same ETag on A and B; B answers 304 to A's ETag; `/api/status` is `no-store` |
| `F-nginx-cache-on.png` | step 3: `nginx -t` ok, the cache directory |
| `F-D1-miss-hit.png` | step 4: `MISS` then five `HIT`s with the same `x-backend` |
| `F-D1-304.png` | step 5: `HTTP/2 304`, no body |
| `F-revalidated-and-log.png` | step 6: `REVALIDATED` + the access log (`MISS` / `HIT` / `REVALIDATED`, `upstream_status=304`) |
| `F-status-not-cached.png` | step 7: `no-store`, A/B alternating |
| `F-safari-devtools.png` | step 8 (optional) |

## Explain it back (viva practice: answer in your own words)

1. What is the difference between **fresh** and **stale**? Which header decides it here?
2. What does a `304` save, and what does it **not** save?
3. Why must `/api/status` be `no-store`? What would the load-balancing demo show if the edge cached it?
4. Why did all the `HIT` responses show the same `x-backend`?
5. Why is the ETag the same on Backend A and Backend B, and what would break if it weren't?
6. `ETag` vs `Last-Modified`: which one wins if a client sends both, and why is an ETag more precise?
7. What is the risk of a long `max-age`? How is it similar to the DNS TTL from Task B?
8. Where else could this response be cached on its way to the user? (browser, edge/CDN, …)
9. Which cloud service plays the edge-cache role? (CloudFront, Cloudflare, Akamai …)

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `/api/info` returns `404` | the new `server.py` isn't installed or the service wasn't restarted (step 1) |
| no `x-cache-status` header | the new nginx config isn't loaded: redo step 3; check that the URL path is exactly `/api/info` |
| always `MISS`, never `HIT` | the backend response has no `Cache-Control: max-age` (old `server.py` on one backend?): `curl -sI http://192.168.64.13:3001/api/info` and `…14:3002…` |
| conditional request returns `200`, not `304` | the ETag wasn't copied exactly (quotes included): `echo "$ETAG"` must show `"…"` with the quotes |
| `nginx -t`: `mkdir() "/var/cache/nginx-teamvks" failed` | run `nginx -t` with `sudo` |
| `sleep 61` shows `EXPIRED` instead of `REVALIDATED` | the backend answered `200` instead of `304`: check that both backends run the new code (same ETag) |
