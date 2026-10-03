# Phase 1 form answers

Text to paste into the Google Form, taken from the real output in this folder. The form asks for actual terminal output, so where a box has room, paste the raw `.txt` file instead of the summary.

## General

| Field | Answer |
| --- | --- |
| Team name / number | `teamvks` (solo) |
| Submission type | Type 3 – Virtual machines (UTM) |
| GitHub repository URL | https://github.com/vks-g/cn-private-network-platform |
| Recording Drive link | _after the video is recorded_ |
| Student names and enrollment numbers | `2401020094 Gokul VKS` |

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

## A2 – dnsmasq configuration

```text
interface=enp0s1
listen-address=192.168.64.11
bind-dynamic
local=/teamvks.test/
address=/app.teamvks.test/192.168.64.12
address=/api.teamvks.test/192.168.64.12
no-resolv
server=192.168.64.1
domain-needed
bogus-priv
log-queries
```

Source: `/etc/dnsmasq.d/teamvks.conf` on vm1-dns (comments stripped). Full commented file: [configs/vm1-dns/dnsmasq.d/teamvks.conf](../../configs/vm1-dns/dnsmasq.d/teamvks.conf)

## A3 – `dig app.teamvks.test` from a client (vm4-backend-b)

```text
; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> app.teamvks.test
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 33458
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;app.teamvks.test.		IN	A

;; ANSWER SECTION:
app.teamvks.test.	0	IN	A	192.168.64.12

;; Query time: 3 msec
;; SERVER: 192.168.64.11#53(192.168.64.11) (UDP)
;; WHEN: Sat Oct 03 17:08:46 UTC 2026
;; MSG SIZE  rcvd: 61
```

Source: [A-lan-dns/A3-dig-app-from-vm4.txt](A-lan-dns/A3-dig-app-from-vm4.txt). ANSWER = the edge `192.168.64.12`; SERVER = our DNS `192.168.64.11`. vm2-edge gives the same result: [A3-dig-app-from-vm2.txt](A-lan-dns/A3-dig-app-from-vm2.txt).

## A4 – `dig @8.8.8.8 app.teamvks.test`

```text
; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> @8.8.8.8 app.teamvks.test
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 33191
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 512
;; QUESTION SECTION:
;app.teamvks.test.		IN	A

;; AUTHORITY SECTION:
.			85695	IN	SOA	a.root-servers.net. nstld.verisign-grs.com. 2026100300 1800 900 604800 86400

;; Query time: 182 msec
;; SERVER: 8.8.8.8#53(8.8.8.8) (UDP)
;; WHEN: Sat Oct 03 17:08:46 UTC 2026
;; MSG SIZE  rcvd: 120
```

Source: [A-lan-dns/A4-dig-8.8.8.8-nxdomain.txt](A-lan-dns/A4-dig-8.8.8.8-nxdomain.txt). `NXDOMAIN`: the name exists only on our private DNS.

## B1 – `curl -v https://app.teamvks.test` (no `-k`), from vm4-backend-b

```text
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed

  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0* Host app.teamvks.test:443 was resolved.
* IPv6: (none)
* IPv4: 192.168.64.12
*   Trying 192.168.64.12:443...
* Connected to app.teamvks.test (192.168.64.12) port 443
* ALPN: curl offers h2,http/1.1
} [5 bytes data]
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
} [512 bytes data]
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
{ [5 bytes data]
* TLSv1.3 (IN), TLS handshake, Server hello (2):
{ [122 bytes data]
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
{ [19 bytes data]
* TLSv1.3 (IN), TLS handshake, Certificate (11):
{ [952 bytes data]
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
{ [264 bytes data]
* TLSv1.3 (IN), TLS handshake, Finished (20):
{ [52 bytes data]
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
} [1 bytes data]
* TLSv1.3 (OUT), TLS handshake, Finished (20):
} [52 bytes data]
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=app.teamvks.test; O=teamvks CN Project
*  start date: Oct  3 19:44:50 2026 GMT
*  expire date: Nov  4 19:44:50 2027 GMT
*  subjectAltName: host "app.teamvks.test" matched cert's "app.teamvks.test"
*  issuer: CN=teamvks Lab Root CA; O=teamvks CN Project
*  SSL certificate verify ok.
*   Certificate level 0: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
} [5 bytes data]
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://app.teamvks.test/
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: app.teamvks.test]
* [HTTP/2] [1] [:path: /]
* [HTTP/2] [1] [user-agent: curl/8.5.0]
* [HTTP/2] [1] [accept: */*]
} [5 bytes data]
> GET / HTTP/2
> Host: app.teamvks.test
> User-Agent: curl/8.5.0
> Accept: */*
> 
{ [5 bytes data]
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
{ [281 bytes data]
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
{ [265 bytes data]
* old SSL session ID is stale, removing
{ [5 bytes data]
< HTTP/2 200 
< server: nginx/1.24.0 (Ubuntu)
< date: Sat, 03 Oct 2026 19:52:55 GMT
< content-type: text/html; charset=utf-8
< content-length: 392
< x-backend: A
< 
{ [392 bytes data]

100   392  100   392    0     0   9269      0 --:--:-- --:--:-- --:--:--  9560
* Connection #0 to host app.teamvks.test left intact
<!doctype html><meta charset=utf-8><title>teamvks - Backend A</title><h1>Backend A is running</h1><table><tr><th>Backend</th><td>A</td></tr><tr><th>Host</th><td>vm3-backend-a, port 3001</td></tr><tr><th>TCP connection from</th><td>192.168.64.12</td></tr><tr><th>Original client (X-Forwarded-For)</th><td>192.168.64.14</td></tr></table><p>JSON status: <a href="/api/status">/api/status</a></p>
```

Source: [B-https-lb/E-B1-curl-v.txt](B-https-lb/E-B1-curl-v.txt). Certificate issued by our local CA `teamvks Lab Root CA`, trusted on every client; SAN matches `app.teamvks.test`; `SSL certificate verify ok`.

## B2 – 6 HTTPS requests showing both backends

```text
HTTP/2 200 
x-backend: B
{"backend": "B", "status": "ok", "host": "vm4-backend-b"}
HTTP/2 200 
x-backend: A
{"backend": "A", "status": "ok", "host": "vm3-backend-a"}
HTTP/2 200 
x-backend: B
{"backend": "B", "status": "ok", "host": "vm4-backend-b"}
HTTP/2 200 
x-backend: A
{"backend": "A", "status": "ok", "host": "vm3-backend-a"}
HTTP/2 200 
x-backend: B
{"backend": "B", "status": "ok", "host": "vm4-backend-b"}
HTTP/2 200 
x-backend: A
{"backend": "A", "status": "ok", "host": "vm3-backend-a"}
```

Source: [B-https-lb/E-B2-lb-6x-https.txt](B-https-lb/E-B2-lb-6x-https.txt). Round-robin: B, A, B, A, B, A.

## B3 – nginx upstream and server blocks

```nginx
log_format teamvks '$remote_addr:$remote_port "$request" $status '
                   'tls=$ssl_protocol/$ssl_cipher '
                   'upstream=$upstream_addr upstream_status=$upstream_status '
                   'upstream_time=$upstream_response_time';
upstream teamvks_backends {
    zone teamvks_backends 64k;
    server 192.168.64.13:3001 max_fails=1 fail_timeout=10s;   # Backend A (vm3)
    server 192.168.64.14:3002 max_fails=1 fail_timeout=10s;   # Backend B (vm4)
}
server {
    listen 80;
    server_name app.teamvks.test api.teamvks.test;
    access_log /var/log/nginx/teamvks-access.log teamvks;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name app.teamvks.test api.teamvks.test;
    ssl_certificate     /etc/nginx/tls/teamvks-server.crt;
    ssl_certificate_key /etc/nginx/tls/teamvks-server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    access_log /var/log/nginx/teamvks-access.log teamvks;
    location / {
        proxy_pass http://teamvks_backends;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout     2s;
        proxy_next_upstream       error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}
```

Source: `/etc/nginx/sites-available/teamvks` on vm2-edge (comments stripped). Full commented file: [configs/vm2-edge/nginx/teamvks.conf](../../configs/vm2-edge/nginx/teamvks.conf)

## D1 – Response headers of the cache-enabled endpoint (`/api/info`)

Caching is implemented on **`GET /api/info`** (backends set the headers; the edge vm2 also caches it). `/` and `/api/status` are deliberately `no-store`.

First request (edge had no copy):

```text
$ curl -sI https://app.teamvks.test/api/info
HTTP/2 200 
server: nginx/1.24.0 (Ubuntu)
date: Sat, 03 Oct 2026 20:16:14 GMT
content-type: application/json
content-length: 149
cache-control: public, max-age=60
etag: "2f9bf8e0a1ee62ec"
last-modified: Sat, 03 Oct 2026 18:00:00 GMT
x-backend: A
x-cache-status: MISS
```

Conditional request with the ETag (cache effect):

```text
$ curl -si -H 'If-None-Match: "2f9bf8e0a1ee62ec"' https://app.teamvks.test/api/info
HTTP/2 304 
server: nginx/1.24.0 (Ubuntu)
date: Sat, 03 Oct 2026 20:16:39 GMT
cache-control: public, max-age=60
etag: "2f9bf8e0a1ee62ec"
last-modified: Sat, 03 Oct 2026 18:00:00 GMT
x-backend: A
x-cache-status: HIT
```

Repeated requests while fresh:

```text
x-backend: B x-cache-status: HIT
x-backend: B x-cache-status: HIT
x-backend: B x-cache-status: HIT
x-backend: B x-cache-status: HIT
x-backend: B x-cache-status: HIT
```

Sources: [F-D1-headers.txt](D-caching-failures/F-D1-headers.txt) · [F-D1-304.txt](D-caching-failures/F-D1-304.txt) · [F-edge-hits.txt](D-caching-failures/F-edge-hits.txt) · [F-edge-log.txt](D-caching-failures/F-edge-log.txt)

## D2 – Explain `max-age`, `ETag` and `304` (2–4 sentences, **write this yourself**)

_Write it in your own words from what you observed. Points to cover: what `max-age=60` let the edge do (5× HIT, no backend contacted); what the ETag is and why A and B share it (the copy fetched from B was confirmed by A); what the 304 saved (the body) and what it didn't (the round trip)._

## C · D3

_Filled in as each task is completed._
