# Task G: Wireshark – DNS → TCP → TLS → HTTP on the wire

**Goal:** one clean packet capture that shows a full request to `https://app.teamvks.test`:

1. the DNS question and answer;
2. the TCP three-way handshake;
3. the TLS handshake with the certificate;
4. the encrypted HTTP that follows.

A second capture at the edge shows TLS termination: encrypted on one side of vm2, plain HTTP on the other.

**Brief says:**
- capture DNS (query + response), the TCP handshake (SYN, SYN-ACK, ACK), the TLS handshake (ClientHello, ServerHello, Certificate) and encrypted HTTP;
- identify source/destination IPs and ports, the DNS answer and TTL, and the TLS version/cipher;
- explain each layer.

**Form fields:** C1 (DNS), C2 (TCP handshake), C3 (TLS handshake + encrypted data)

Commands are labelled with **where** to run them: a VM's SSH pane, the **Mac**, or **Wireshark** (the app on the Mac).

## Concepts to understand first

| Term | In this lab |
| --- | --- |
| Capture point | where the "tap" sits. We capture on the **client VM's switch port** (`vmenetN` on the Mac), so we see exactly what vm4 sends and receives |
| Capture filter | decides what gets **recorded** (BPF syntax: `not port 22`). We drop our own SSH session so the file stays clean |
| Display filter | decides what is **shown** from what was recorded (Wireshark syntax: `dns`, `tcp.stream eq 0`) |
| TCP stream | Wireshark's number for one TCP connection (one 4-tuple: client IP:port ↔ server IP:port) |
| Relative vs raw sequence numbers | Wireshark shows seq/ack counted from 0 for readability. The real (raw) values are random 32-bit numbers, shown as "Sequence Number (raw)" |
| TLS 1.2 vs 1.3 on the wire | TLS 1.2 sends the **Certificate in clear**. In TLS 1.3 everything after ServerHello is encrypted, so the certificate is invisible. That's why we capture one of each |

Layers you'll see in **every** packet (the middle pane, top to bottom):

| Wireshark line | Layer | Example |
| --- | --- | --- |
| Frame | – | length, arrival time |
| Ethernet II | 2 Link | `Src: 92:b1:96:9b:dc:31` (vm4) → `Dst: 6a:9b:d7:70:ed:9d` (vm2) |
| Internet Protocol Version 4 | 3 Network | `192.168.64.14 → 192.168.64.12`, TTL 64 |
| UDP or TCP | 4 Transport | ports, flags, seq/ack |
| DNS / TLS / HTTP | 5–7 Application | the actual message |

## 1. Find vm4's switch port (Mac)

Port numbers follow VM start order and **change after a VM restart** (vm3 rebooted in Task C), so map them again:

```bash
ifconfig bridge100 | sed -n '/Address cache/,$p'
```

Find the line with vm4's MAC **`92:b1:96:9b:dc:31`** and note its `vmenetN`. Also note vm2's (`6a:9b:d7:70:ed:9d`); you'll need it in step 8.

## 2. Start the capture (Wireshark)

1. Quit any running capture (■). Then **Capture → Options…**.
2. Select **vm4's `vmenetN`**. If it's missing, use **Capture → Refresh Interfaces**.
3. In **"Capture filter for selected interfaces"** type: `not port 22`.
4. Click **Start**.

`not port 22` drops your Mac↔vm4 SSH session, which also crosses this port. Without it, every keystroke you type would end up in the capture.

Tip for screenshots and the video: **View → Zoom In** (Cmd +) once or twice.

## 3. Generate the traffic (vm4 pane)

Run these **one at a time**, a few seconds apart:

```bash
dig app.teamvks.test
curl -s --tls-max 1.2 https://app.teamvks.test/api/status
curl -s --tlsv1.3 https://app.teamvks.test/api/status
```

| Command | Produces |
| --- | --- |
| `dig` | one clean DNS query + response (UDP 53) |
| `curl --tls-max 1.2` | DNS (A + AAAA), TCP handshake, a **TLS 1.2** handshake with the **Certificate visible**, encrypted HTTP/2, TCP close |
| `curl --tlsv1.3` | the same request with **TLS 1.3**, for the comparison in step 7 |

Then **stop** the capture (■) and save it:

**Mac:**

```bash
mkdir -p ~/Documents/Sem_5_Projects/CN/cn-private-network-platform/evidence/phase1/C-wireshark
```

**Wireshark:** **File → Save As…** → that folder → `phase1-capture.pcapng`.

If nginx happened to pick Backend B for one of the curls, you'll also see a flow `192.168.64.12:<port> → 192.168.64.14:3002`. That's the edge talking to vm4 **as a backend**, in plain HTTP. Step 8 looks at it properly.

## 4. Form C1: DNS (Wireshark)

Display filter (type it in the bar at the top and press Enter):

```text
dns && ip.addr == 192.168.64.11
```

Click the **first** packet (`Standard query … A app.teamvks.test`) and expand the middle pane:

| Where | What to point at |
| --- | --- |
| Internet Protocol | Src `192.168.64.14` (vm4) → Dst `192.168.64.11` (vm1) |
| User Datagram Protocol | Src Port = random ephemeral port, **Dst Port 53** |
| Domain Name System → Queries | `app.teamvks.test: type A, class IN` · Transaction ID `0x….` |

Click the **response** (`Standard query response … A 192.168.64.12`):

| Where | What to point at |
| --- | --- |
| IP / UDP | reversed: `.11:53 → .14:<same port>` · same Transaction ID (that's how the client matches answer to question) |
| Flags | `Response: Message is a response`, **`Authoritative: Server is an authority for domain`** (the `aa` flag from Task B) |
| Answers | `app.teamvks.test: type A, class IN, addr 192.168.64.12` · **`Time to live: 0`** |
| bottom of DNS | `[Time: 0.00… seconds]`: how long the answer took |

The curl lookups also show an **AAAA** query (IPv6 address) that gets an answer with no records (NODATA): we only publish IPv4.

## 5. Form C2: TCP three-way handshake (Wireshark)

Display filter:

```text
tcp.flags.syn == 1 && tcp.port == 443
```

You'll see one SYN and one SYN-ACK per curl. Click the **first SYN** (the TLS 1.2 curl), then right-click → **Conversation Filter → TCP**. The filter becomes `tcp.stream eq N`, which is that one connection. The first three packets are the handshake:

| # | Direction | Flags | Seq / Ack (relative) | What to point at |
| --- | --- | --- | --- | --- |
| 1 | `.14:<eph> → .12:443` | **SYN** | Seq 0 | client's ephemeral port; Options: **MSS 1460**, SACK permitted, timestamps, window scale |
| 2 | `.12:443 → .14:<eph>` | **SYN, ACK** | Seq 0, **Ack 1** | the edge accepts: "I got your SYN (seq+1), here is mine" |
| 3 | `.14:<eph> → .12:443` | **ACK** | Seq 1, **Ack 1** | connection established; the next packet is the TLS ClientHello |

Expand **Transmission Control Protocol** in packet 1 and find **"Sequence Number (raw)"**. That's the real random starting number (ISN). Relative `0` is just Wireshark subtracting it for you. Note the raw values of SYN and SYN-ACK; the form asks for sequence values.

**Wireshark: Statistics → Flow Graph**, tick *Limit to display filter*, flow type *TCP Flows*. You get a ladder diagram of the whole connection: handshake, data, and the FIN/ACK close at the end.

## 6. Form C3: TLS 1.2 handshake (Wireshark)

Keep the same stream and show only TLS:

```text
tcp.stream eq N && tls
```

| Packet (Info column) | Expand | What to point at |
| --- | --- | --- |
| **Client Hello (SNI=app.teamvks.test)** | TLS → Handshake Protocol: Client Hello | Version TLS 1.2; **Cipher Suites**: the long list the client offers; extension `server_name` = `app.teamvks.test` (sent in **clear text**); ALPN `h2, http/1.1` |
| **Server Hello, Certificate, Server Key Exchange, Server Hello Done** (may be split over 2 packets) | Server Hello | the **one** cipher the server chose from that list. Your Task E access log showed `ECDHE-RSA-AES256-GCM-SHA384`, which Wireshark names `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 (0xc030)`; ALPN `h2` |
| ↳ same packet | Certificate → `signedCertificate` | `subject: CN=app.teamvks.test`, `issuer: CN=teamvks Lab Root CA`, validity, `extensions → subjectAltName: app.teamvks.test, api.teamvks.test` |
| ↳ same packet | Server Key Exchange | ECDHE curve (`x25519`) + the server's public value, **signed** with its RSA key |
| **Client Key Exchange, Change Cipher Spec, Encrypted Handshake Message** | | client's ECDHE value; from here on the client encrypts |
| **Change Cipher Spec, Encrypted Handshake Message** | | the server switches to encryption too; the "encrypted handshake message" is the `Finished` check |
| **Application Data** | TLS → Encrypted Application Data | opaque bytes: the HTTP/2 request and response. No `/api/status`, no `x-backend` visible |

To read the certificate, expand `Certificate` → `signedCertificate` → `subject`, `issuer`, `validity` and `extensions`. It's the same certificate you signed in Task E, and anyone on the network can read it in TLS 1.2.

## 7. TLS 1.3 vs TLS 1.2 (Wireshark)

Show only handshake **types** from both curls:

```text
tls.handshake.type == 1 || tls.handshake.type == 2 || tls.handshake.type == 11
```

(1 = ClientHello, 2 = ServerHello, 11 = Certificate)

- **TLS 1.2 stream:** ClientHello, ServerHello **and Certificate**.
- **TLS 1.3 stream:** ClientHello and ServerHello only. The certificate exists, but it travels inside the encrypted records right after ServerHello. Open that ServerHello: the record says TLS 1.2 for compatibility, but the extension **`supported_versions: TLS 1.3`** is what counts.

## 8. Bonus: TLS termination seen at the edge (Wireshark + vm4 pane)

Start a **new** capture on **vm2's `vmenetN`** with capture filter `not port 22`. Then, in the **vm4 pane**:

```bash
for i in 1 2; do curl -s https://app.teamvks.test/api/status; echo; done
```

Stop and save as `edge-tls-termination.pcapng` in the same folder.

Ports 3001/3002 aren't standard HTTP ports, so tell Wireshark to read them as HTTP: right-click any packet on port 3001 → **Decode As…** → set the row to `TCP port 3001` → `HTTP` → add a second row for `3002` → **OK**.

Display filter:

```text
tcp.port in {443 3001 3002}
```

You'll see two kinds of conversation through the same edge:

| Conversation | What's visible |
| --- | --- |
| `.14 → .12:443` (client → edge) | TCP + TLS only: **Application Data**, unreadable |
| `.12 → .13:3001` / `.12 → .14:3002` (edge → backend) | a fresh TCP handshake from the edge, then **`GET /api/status HTTP/1.1`** in clear text with `Host`, **`X-Forwarded-For: 192.168.64.14`**, **`X-Forwarded-Proto: https`**, and the backend's JSON + `X-Backend` header |

Right-click a 3001 packet → **Follow → HTTP Stream** to read the whole request and response. That's TLS termination: the edge decrypted the client's request and made its own plain request on the private LAN.

## 9. Text versions for the form (Mac)

The form wants descriptions with exact values. These `tshark` commands (Wireshark's command-line twin) print them from your saved capture:

```bash
cd ~/Documents/Sem_5_Projects/CN/cn-private-network-platform/evidence/phase1/C-wireshark
P=phase1-capture.pcapng
S12=$(tshark -r $P -Y 'tls.handshake.type == 11' -T fields -e tcp.stream | head -1)
echo "TLS 1.2 stream = $S12"

# C1: DNS (dig + curl lookups)
tshark -r $P -Y 'dns' -T fields -E header=y -E separator=' | ' \
  -e frame.number -e ip.src -e udp.srcport -e ip.dst -e udp.dstport -e dns.id -e dns.flags.response \
  -e dns.qry.name -e dns.qry.type -e dns.a -e dns.resp.ttl -e dns.flags.authoritative | tee C1-dns.txt

# C2: TCP handshake of the TLS 1.2 connection
tshark -r $P -Y "tcp.stream == $S12 && (tcp.flags.syn == 1 || (tcp.seq == 1 && tcp.ack == 1 && tcp.len == 0))" \
  -T fields -E header=y -E separator=' | ' -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
  -e tcp.flags.str -e tcp.seq -e tcp.seq_raw -e tcp.ack -e tcp.ack_raw -e tcp.options.mss_val | head -4 | tee C2-tcp-handshake.txt

# C3: TLS 1.2 handshake + details
{ tshark -r $P -Y "tcp.stream == $S12 && tls"
  echo; tshark -r $P -Y "tcp.stream == $S12 && tls.handshake.type == 1" -T fields -E header=y -E separator=' | ' \
    -e tls.handshake.extensions_server_name -e tls.handshake.extensions_alpn_str -e tls.handshake.ciphersuite
  echo; tshark -r $P -Y "tcp.stream == $S12 && tls.handshake.type == 2" -T fields -E header=y -E separator=' | ' \
    -e tls.handshake.version -e tls.handshake.ciphersuite -e tls.handshake.extensions_alpn_str
  echo; tshark -r $P -Y "tcp.stream == $S12 && tls.handshake.type == 11" -T fields -E header=y -E separator=' | ' \
    -e x509sat.uTF8String -e x509ce.dNSName -e x509af.utcTime
} | tee C3-tls12-handshake.txt

# TLS 1.3 for comparison
tshark -r $P -Y 'tls.handshake.extensions.supported_version == 0x0304 && tls.handshake.type == 2' -T fields -e tcp.stream \
  | head -1 | xargs -I{} tshark -r $P -Y 'tcp.stream == {} && tls' | tee C3-tls13-comparison.txt
```

`tls.handshake.ciphersuite` prints hex codes (`0xc030` = `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`); the GUI shows the names.

## 10. Optional: decrypt the TLS traffic

TLS can be decrypted only with the **session secrets**, not with any certificate. curl can write them to a file:

**vm4 pane** (run while capturing on vm4's port again):

```bash
SSLKEYLOGFILE=~/sslkeys.log curl -s https://app.teamvks.test/api/status
```

**Mac:** copy the file **outside the repo**:

```bash
scp vm4:sslkeys.log ~/Desktop/sslkeys.log
```

**Wireshark → Settings → Protocols → TLS → (Pre)-Master-Secret log filename** → pick `~/Desktop/sslkeys.log`. The Application Data turns into readable **HTTP/2 HEADERS and DATA frames** (`:path /api/status`, `x-backend`, the JSON).

Delete both copies afterwards (`rm ~/Desktop/sslkeys.log`; on vm4 `rm ~/sslkeys.log`). `.gitignore` already blocks `sslkeys*.log`. Anyone holding that file can read the session.

## 📸 Screenshots for this task (save to `evidence/phase1/_inbox/`)

| File name (we'll rename together) | What it shows |
| --- | --- |
| `G-port-map.png` | step 1: `ifconfig bridge100` address cache, vm4's `vmenetN` |
| `G-capture-options.png` | step 2: vm4's port selected, capture filter `not port 22` |
| `G-C1-dns-query.png` | step 4: query expanded (IPs, UDP 53, name, transaction ID) |
| `G-C1-dns-response.png` | step 4: response expanded (answer `192.168.64.12`, TTL 0, authoritative) |
| `G-C2-tcp-handshake.png` | step 5: SYN / SYN-ACK / ACK with the SYN's TCP header expanded (ports, flags, raw seq, MSS) |
| `G-C2-flow-graph.png` | step 5: Statistics → Flow Graph |
| `G-C3-client-hello.png` | step 6: SNI, cipher suites, ALPN |
| `G-C3-server-hello-certificate.png` | step 6: chosen cipher + certificate subject/issuer/SAN |
| `G-C3-ccs-app-data.png` | step 6: Change Cipher Spec + encrypted Application Data |
| `G-tls13-vs-tls12.png` | step 7: Certificate only in the TLS 1.2 stream |
| `G-edge-plaintext-backend.png` | step 8: 443 encrypted vs 3001/3002 plain HTTP with `X-Forwarded-For` |
| `G-decrypted-http2.png` | step 10 (optional) |

## Explain it back (viva practice: answer in your own words)

1. Why does DNS use UDP here, and how does the client match the response to its query?
2. What would the TTL in the DNS answer change if it were 30 instead of 0?
3. Why are relative sequence numbers 0 and 1, while the raw ones are huge random numbers? Why random?
4. What does each of SYN, SYN-ACK and ACK prove? Why does the ACK number equal the other side's seq + 1?
5. What is MSS, and why 1460?
6. Which parts of the TLS 1.2 handshake can an eavesdropper read? (SNI, certificate, offered ciphers …) What changes in TLS 1.3?
7. What does `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384` mean, part by part?
8. Why can't you decrypt the capture even though you have the server's private key? (forward secrecy)
9. In step 8, where exactly is TLS terminated, and why is the edge→backend traffic readable?
10. Why couldn't we just capture on `bridge100` for all of this? (Task A, step 10)
11. Point to each OSI layer in one packet's details pane.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| The `vmenetN` from step 1 isn't in Wireshark's list | Capture → Refresh Interfaces; make sure the VM is running |
| Capture is full of SSH packets | the capture filter is missing: `not port 22` goes in the *capture* filter box, before Start |
| No DNS packets at all | dig was run before the capture started, or vm4 isn't using vm1: `grep nameserver /etc/resolv.conf` |
| Only one TLS stream / no Certificate packet | the `--tls-max 1.2` curl was skipped or run outside the capture: repeat steps 2–3 |
| Ports 3001/3002 show as plain TCP "data" | do the **Decode As…** step (step 8) |
| `tshark: command not found` on the Mac | use the full path `/Applications/Wireshark.app/Contents/MacOS/tshark` |
| `tshark` prints nothing for C2 | `S12` is empty: check `echo $S12`; the capture has no TLS 1.2 Certificate packet |
