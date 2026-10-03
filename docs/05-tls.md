# Task E: HTTPS with our own certificate authority

**Goal:** clients open `https://app.teamvks.test` and the connection is encrypted **and** verified: no warnings and no `curl -k`. TLS ends at the edge (vm2), and nginx still load-balances to the backends over the private LAN. Plain `http://` now only redirects to HTTPS.

**Brief says:**
- terminate TLS at Mac 2 (the edge);
- use a certificate the clients trust: a local CA, or self-signed with documented trust steps;
- the domain must match the certificate;
- show the certificate in the browser and verify with `curl -v`;
- explain TLS termination.

**Form fields:** B1 (`curl -v https://app.teamvks.test`, no `-k`), B2 (6 HTTPS responses with both `X-Backend` values), B3 (nginx upstream + server blocks)

Commands are labelled with **where** to run them: a VM's SSH pane or the **Mac**.

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Key pair | a **private key** (kept secret) and a matching **public key**. What one signs, the other can verify |
| Certificate | a public key + names (`app.teamvks.test`) + validity dates, **signed** by a CA. It says "this key belongs to this name" |
| CA (certificate authority) | the signer everyone trusts. Here it's *you*: `teamvks Lab Root CA`, made on the Mac |
| CSR (certificate signing request) | "please certify my public key for these names", made on vm2 and sent to the CA. It contains the public key, **never** the private key |
| SAN (subject alternative name) | the list of names a certificate is valid for. Clients compare the URL's hostname with it; the old Common Name is ignored |
| Chain of trust | client trusts the CA → the CA signed the edge certificate → the client trusts the edge certificate |
| TLS termination | the edge decrypts. Client ↔ edge is encrypted; edge ↔ backend is a separate plain-HTTP connection on the private LAN |
| ALPN | TLS extension where client and server agree on HTTP/2 (`h2`) or HTTP/1.1 during the handshake |

Why not just a self-signed certificate on nginx? It would work, but every client would have to trust that one server certificate. With a CA, clients trust the CA **once**, and any certificate it signs later (a second edge in Phase 2, a new name) is trusted automatically. That's how the real web works, and in the cloud it's AWS Certificate Manager / AWS Private CA.

## 1. Create the CA (Mac)

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform/tls
cat ca.cnf
mkdir -p private && chmod 700 private
openssl genrsa -out private/teamvks-ca.key 2048
openssl req -x509 -new -key private/teamvks-ca.key -sha256 -days 1825 -config ca.cnf -out teamvks-ca.crt
openssl x509 -in teamvks-ca.crt -noout -subject -issuer -dates -ext basicConstraints,keyUsage
```

| Command | What it does |
| --- | --- |
| `genrsa … 2048` | the CA's private key: 2048-bit RSA. It stays in `tls/private/`, which git ignores |
| `req -x509 -new …` | builds the CA certificate and signs it **with its own key** (a root CA is self-signed) |
| `-config ca.cnf` | name `teamvks Lab Root CA`, `CA:TRUE`, and the key may only sign certificates |
| `-days 1825` | valid for 5 years |

**Expect:** `subject` and `issuer` are **the same** (`CN=teamvks Lab Root CA`, which is what self-signed means), `CA:TRUE`, and `Certificate Sign, CRL Sign`.

## 2. Create the edge's key and CSR (vm2 pane)

The edge makes its **own** private key, so the key never has to travel over the network.

```bash
mkdir -p ~/tls && cd ~/tls
openssl req -new -newkey rsa:2048 -nodes -keyout teamvks-server.key -out teamvks-server.csr -subj "/CN=app.teamvks.test/O=teamvks CN Project"
chmod 600 teamvks-server.key
openssl req -in teamvks-server.csr -noout -subject -verify
```

- `-nodes` = "no DES": the key isn't password-protected, so nginx can start unattended.
- **Expect:** `subject=CN=app.teamvks.test, O=teamvks CN Project` and `Certificate request self-signature ok`. vm2 signed its own CSR, which proves it holds the matching private key.

## 3. Sign the CSR with the CA (Mac)

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform/tls
scp vm2:tls/teamvks-server.csr private/
cat server.ext
openssl x509 -req -in private/teamvks-server.csr -CA teamvks-ca.crt -CAkey private/teamvks-ca.key -CAcreateserial -days 397 -sha256 -extfile server.ext -out teamvks-server.crt
openssl verify -CAfile teamvks-ca.crt teamvks-server.crt
openssl x509 -in teamvks-server.crt -noout -subject -issuer -dates -ext subjectAltName,extendedKeyUsage
```

| Option | Meaning |
| --- | --- |
| `-CA` / `-CAkey` | sign with the CA certificate and the CA's private key |
| `-CAcreateserial` | give the certificate a serial number (stored in `teamvks-ca.srl`, git-ignored) |
| `-days 397` | about 13 months. Apple devices reject server certificates valid for more than 825 days, and browsers prefer ≤ 398 |
| `-extfile server.ext` | adds the SAN names, `serverAuth` and `CA:FALSE` |

**Expect:** `teamvks-server.crt: OK`, issuer `teamvks Lab Root CA`, and `DNS:app.teamvks.test, DNS:api.teamvks.test`.

Send the results out: the edge certificate goes to vm2, and the CA certificate goes to every VM.

```bash
scp teamvks-server.crt vm2:tls/
for h in vm1 vm2 vm3 vm4; do scp teamvks-ca.crt "${h}:"; done
git status --short .
```

`git status` should list only `teamvks-ca.crt` and `teamvks-server.crt`. Nothing from `private/` appears, because git ignores it.

## 4. Install the certificate and switch nginx to HTTPS (vm2 pane)

```bash
sudo install -d -m 755 /etc/nginx/tls
sudo install -m 644 ~/tls/teamvks-server.crt /etc/nginx/tls/teamvks-server.crt
sudo install -m 600 ~/tls/teamvks-server.key /etc/nginx/tls/teamvks-server.key
rm ~/tls/teamvks-server.key
sudo ls -l /etc/nginx/tls
cd ~/cn && git pull
sudo install -m 644 ~/cn/configs/vm2-edge/nginx/teamvks.conf /etc/nginx/sites-available/teamvks
sudo nginx -t
sudo systemctl reload nginx
sudo ss -ltnp '( sport = :80 or sport = :443 )'
```

- The key is mode `600` and owned by root. nginx's master process (root) reads it at start-up; the workers never need it.
- `rm ~/tls/teamvks-server.key` leaves only the protected copy.
- **Expect:** `nginx -t` successful, plus nginx listening on **both** `0.0.0.0:80` and `0.0.0.0:443`.

What changed in the config (`git diff` or read the file):

- a new `server { listen 443 ssl http2; … }` with `ssl_certificate`, `ssl_certificate_key` and `ssl_protocols TLSv1.2 TLSv1.3`;
- the port-80 server now only does `return 301 https://$host$request_uri;`;
- the log line gains `tls=$ssl_protocol/$ssl_cipher`.

## 5. Try it before trusting the CA (vm4 pane)

```bash
curl -sS https://app.teamvks.test/api/status; echo "exit code: $?"
```

**Expect:** `curl: (60) SSL certificate problem: unable to get local issuer certificate`. The certificate is fine, but vm4 doesn't know our CA yet, so it can't verify the chain. **Never "fix" this with `-k`:** that switches off verification entirely, and anyone in the middle could pretend to be the edge.

## 6. Trust the CA on every VM (all four panes)

```bash
sudo install -m 644 ~/teamvks-ca.crt /usr/local/share/ca-certificates/teamvks-ca.crt
sudo update-ca-certificates
```

**Expect:** `1 added, 0 removed; done.` The CA is now part of the system trust store (`/etc/ssl/certs/ca-certificates.crt`) that curl and OpenSSL use.

## 7. Form B1: verified HTTPS (vm4 pane)

```bash
mkdir -p ~/evidence
curl -v https://app.teamvks.test 2>&1 | tee ~/evidence/E-B1-curl-v.txt
```

`curl -v` writes its handshake details to stderr; `2>&1` sends them into the file too. Find these lines:

| Line | Means |
| --- | --- |
| `Connected to app.teamvks.test (192.168.64.12) port 443` | DNS gave the edge's IP; TCP to port 443 is open |
| `ALPN: curl offers h2,http/1.1` … `server accepted h2` | HTTP/2 agreed inside the TLS handshake |
| `SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384` | TLS version and cipher |
| `subject: CN=app.teamvks.test` · `issuer: CN=teamvks Lab Root CA` | which certificate and who signed it |
| `subjectAltName: host "app.teamvks.test" matched cert's "app.teamvks.test"` | the name check passed |
| `SSL certificate verify ok.` | the chain check passed: no `-k` needed |
| `< HTTP/2 200` · `< x-backend: …` | the response through the encrypted tunnel; HTTP/2 header names are lowercase |

## 8. Form B2: load balancing over HTTPS (vm4 pane)

```bash
for i in 1 2 3 4 5 6; do curl -si https://app.teamvks.test/api/status | grep -iE '^HTTP/|^x-backend|"backend"'; done | tee ~/evidence/E-B2-lb-6x-https.txt
```

**Expect:** six blocks of `HTTP/2 200`, `x-backend: A` or `B`, and the JSON line, alternating A, B, A, B, …

## 9. Redirect, HTTP versions and TLS versions (vm4 pane)

```bash
curl -sI http://app.teamvks.test/api/status | grep -iE '^HTTP/|^location' | tee ~/evidence/E-http-redirect.txt
curl -sI --http1.1 https://app.teamvks.test/api/status | head -1
curl -sI --http2   https://app.teamvks.test/api/status | head -1
curl -sI --tls-max 1.2 https://app.teamvks.test/api/status | head -1
```

**Expect:**

- `HTTP/1.1 301 Moved Permanently` + `Location: https://app.teamvks.test/api/status`: plain HTTP is only a signpost now;
- `HTTP/1.1 200` and `HTTP/2 200`: the client picks, and ALPN agrees;
- the TLS 1.2 request also works. It matters in Task G, because in TLS 1.3 the certificate travels **encrypted**, so Wireshark only shows it in a TLS 1.2 handshake.

## 10. The edge's view (vm2 pane)

```bash
mkdir -p ~/evidence
grep -Ev '^\s*(#|$)' /etc/nginx/sites-available/teamvks | tee ~/evidence/E-B3-nginx-conf.txt
tail -n 10 /var/log/nginx/teamvks-access.log | tee ~/evidence/E-access-log-https.txt
```

- The first file is form **B3**: the `upstream` block and both `server` blocks.
- In the log, see `"GET /api/status HTTP/2.0"` vs `HTTP/1.1`, `tls=TLSv1.3/TLS_AES_256_GCM_SHA384` vs `tls=TLSv1.2/ECDHE-RSA-AES256-GCM-SHA384`, the redirect as `301` with `tls=-/-`, and `upstream=` still alternating. The backends never saw any TLS.

## 11. The Mac and Safari (Mac)

Trust the CA in the **System** keychain. Run `sudo -v` alone first and enter your Mac password, then:

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain tls/teamvks-ca.crt
curl -v https://app.teamvks.test/api/status 2>&1 | grep -iE 'certificate|subject|issuer|SSL|ALPN|HTTP/|x-backend'
```

macOS may also ask for your password in a pop-up. The Mac's `curl` uses Apple's TLS library, which trusts the System keychain, so it verifies without `-k` too.

Then in **Safari**, open `http://app.teamvks.test/` (plain HTTP on purpose):

1. it jumps to **https://** by itself (the 301);
2. the address bar shows a **padlock** and no warning;
3. click the padlock → **Show Certificate**: the chain is `teamvks Lab Root CA` → `app.teamvks.test`, with the SAN names and dates.

To check the trust visually: **Keychain Access** → System → Certificates → `teamvks Lab Root CA` → "This certificate is marked as trusted for all users".

## 12. Copy the evidence into the repo (Mac)

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform
for h in vm2 vm4; do scp "${h}:evidence/E-*" evidence/phase1/B-https-lb/; done
```

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `E-ca-created.png` | step 1: CA subject = issuer, `CA:TRUE` |
| `E-csr-on-vm2.png` | step 2: CSR subject + self-signature ok |
| `E-cert-signed.png` | step 3: `verify OK`, issuer, SAN names, `git status` without `private/` |
| `E-nginx-443.png` | step 4: key mode 600, `nginx -t` ok, listening on 80 and 443 |
| `E-untrusted-error.png` | step 5: `curl: (60) … unable to get local issuer certificate` |
| `E-trust-vms.png` | step 6: `1 added` |
| `E-B1-curl-v.png` | step 7: `SSL certificate verify ok`, SAN match, `HTTP/2 200` |
| `E-B2-lb-6x-https.png` | step 8: six HTTPS responses alternating A/B |
| `E-redirect-versions.png` | step 9: 301 → https, HTTP/1.1 vs HTTP/2, TLS 1.2 |
| `E-access-log-https.png` | step 10: `HTTP/2.0`, `tls=TLSv1.3/…`, alternating upstreams |
| `E-safari-padlock.png` + `E-safari-cert-chain.png` | step 11: padlock + certificate chain |

## Explain it back (viva practice: answer in your own words)

1. What exactly does a certificate prove, and what does it **not** prove?
2. Why was the edge's private key generated on vm2 instead of on the Mac? What would an attacker gain with it? With the CA key?
3. What does a CSR contain? Why can the CA sign it without ever seeing the private key?
4. Name the checks a client does before it trusts `app.teamvks.test` (chain, name, dates, usage).
5. Why does `curl https://192.168.64.12` fail even with the CA trusted?
6. What does `curl -k` turn off, and why is it forbidden in this project?
7. What is TLS termination? Which hop is encrypted and which isn't? Why is that acceptable here, and when wouldn't it be?
8. Why redirect port 80 instead of closing it?
9. What do TLS 1.2 and TLS 1.3 differ in that you'll see in Wireshark? (Hint: when is the certificate encrypted?)
10. How did client and server agree on HTTP/2? Why does nginx still talk HTTP/1.1 to the backends?
11. Why a CA instead of one self-signed server certificate? Which cloud services do this job?

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `nginx -t`: `cannot load certificate "/etc/nginx/tls/teamvks-server.crt"` | step 4's install lines were skipped, or the file names differ |
| `nginx -t`: `key values mismatch` | the certificate was signed from a different CSR than this key: redo steps 2–4 together |
| `curl: (60) … unable to get local issuer certificate` | CA not trusted on that machine: step 6 (VMs) or step 11 (Mac) |
| `curl: (60) … no alternative certificate subject name matches` | the URL uses a name not in the SAN list (an IP, `vm2`, a typo) |
| `Failed to connect … port 443: Couldn't connect to server` | nginx still has the old config: `sudo ss -ltnp 'sport = :443'`, redo the install + reload |
| `scp vm2:tls/…: No such file or directory` | step 2 didn't run in `~/tls` on vm2 |
| Safari still shows "This Connection Is Not Private" | the CA isn't marked trusted: Keychain Access → System → the certificate → Trust → "Always Trust"; quit and reopen Safari |
| `security: SecTrustSettingsSetTrustSettings: The authorization was denied` | the password prompt was cancelled: run `sudo -v`, then the command again |
