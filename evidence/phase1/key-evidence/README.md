# Phase 1 – key evidence

The 16 screenshots and the packet capture that prove each part of Phase 1, in the order a request travels: LAN → DNS → backends → HTTPS and load balancing → caching → Wireshark → failure. Everything else (raw terminal output, intermediate steps, extra screenshots) is in [`../all-evidence/`](../all-evidence/).

| # | Shows | Brief task · form |
| --- | --- | --- |
| 01 | [Four VMs with their static IPs](01-lan-four-vms-static-ips.png) | A · A1 |
| 02 | [Ping between all six VM pairs, 0% loss](02-lan-ping-all-pairs.png) | A · A5 |
| 03 | [`dig` from vm4: answer `192.168.64.12` from server `192.168.64.11`; `NXDOMAIN` from 8.8.8.8](03-dns-dig-private-and-public.png) | B · A3, A4 |
| 04 | [The edge reaches Backend A (`X-Backend: A`) and Backend B (`X-Backend: B`)](04-backends-reached-from-edge.png) | C |
| 05 | [`curl -v https://app.teamvks.test`: SAN match, `SSL certificate verify ok`, no `-k`](05-https-curl-verified-no-k.png) | E · B1 |
| 06 | [Safari padlock, chain `teamvks Lab Root CA → app.teamvks.test`](06-https-safari-certificate-chain.png) | E |
| 07 | [Six HTTPS requests alternating A / B](07-load-balancing-https-6x.png) | D, E · B2 |
| 08 | [nginx upstream and server blocks + access log with the chosen upstream](08-nginx-config-and-access-log.png) | D, E · B3 |
| 09 | [`/api/info`: `Cache-Control: public, max-age=60`, `ETag`, `X-Cache-Status: MISS`](09-cache-headers-miss.png) | F · D1 |
| 10 | [Conditional request → `304 Not Modified`, answered by the edge cache](10-cache-304-not-modified.png) | F · D1, D2 |
| 11 | [Wireshark: DNS query and response (UDP 53, answer, TTL)](11-wireshark-dns-response.png) | G · C1 |
| 12 | [Wireshark: TCP SYN, SYN-ACK, ACK to port 443](12-wireshark-tcp-handshake.png) | G · C2 |
| 13 | [Wireshark: TLS 1.2 ServerHello and the certificate](13-wireshark-tls-certificate.png) | G · C3 |
| 14 | [Wireshark: encrypted Application Data (HTTP/2 not readable)](14-wireshark-encrypted-http.png) | G · C3 |
| 15 | [Wireshark: the same request from edge to backend in plain HTTP (TLS terminates at the edge)](15-wireshark-tls-termination.png) | G |
| 16 | [Backend A stopped → all `200` from B → A restarted and back in rotation](16-failure-backend-a-down-and-restored.png) | Failure demo · D3 |

**Packet capture:** [`phase1-dns-tcp-tls.pcapng`](phase1-dns-tcp-tls.pcapng), 76 packets captured on vm4's switch port while vm4 ran `dig` and two `curl` requests (TLS 1.2 and TLS 1.3). Open it in Wireshark with the filters `dns`, `tcp.stream eq 0` and `tcp.stream eq 0 && tls`.
