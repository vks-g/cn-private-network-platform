# TLS material (Task E)

The lab runs its own small certificate authority (CA). The CA signs one certificate for the edge (nginx on vm2), and every client trusts the CA.

| File | Public? | Where it lives | Purpose |
| --- | --- | --- | --- |
| [`ca.cnf`](ca.cnf) | yes | repo | OpenSSL settings for the CA certificate (`CA:TRUE`, may only sign certificates) |
| [`server.ext`](server.ext) | yes | repo | extensions written into the edge certificate: SAN `app.teamvks.test`, `api.teamvks.test`, `serverAuth`, `CA:FALSE` |
| `teamvks-ca.crt` | yes | repo, every VM's trust store, Mac System keychain | the CA certificate clients trust |
| `teamvks-server.crt` | yes | repo, vm2 `/etc/nginx/tls/` | the edge certificate, signed by the CA |
| `private/teamvks-ca.key` | **no** | Mac only (`tls/private/`, git-ignored) | signs certificates; whoever has it can impersonate any name |
| `teamvks-server.key` | **no** | vm2 only (`/etc/nginx/tls/`, mode 600) | proves the edge owns the certificate; generated on vm2 and never copied off it |
| `private/teamvks-server.csr` | (public data, not kept) | Mac, git-ignored | the signing request vm2 sent to the CA |

`.gitignore` blocks `tls/private/`, `*.key`, `*.csr` and `*.srl`, so private keys can't be committed by accident.

## Current certificates

| Certificate | Subject | Valid until | SHA-256 fingerprint |
| --- | --- | --- | --- |
| [`teamvks-ca.crt`](teamvks-ca.crt) | `CN=teamvks Lab Root CA, O=teamvks CN Project` | 2 Oct 2031 | `B2:F2:1C:09:A3:2E:96:ED:25:C6:7A:37:63:40:5F:A8:BF:FB:9E:93:33:B9:42:BE:7D:FE:A9:2C:F6:0B:4D:0C` |
| [`teamvks-server.crt`](teamvks-server.crt) | `CN=app.teamvks.test, O=teamvks CN Project`, SAN `app.teamvks.test`, `api.teamvks.test` | 4 Nov 2027 | `7E:5C:B7:28:BB:AF:27:23:BE:96:EA:70:16:B6:7E:BB:46:D9:C1:DD:EF:0B:BC:59:DF:90:DD:4B:18:06:99:1A` |

## How the pieces were made

```text
Mac (CA)                                   vm2 (edge)
--------                                   ----------
1. CA key + self-signed CA cert
                                           2. server key + CSR  (key never leaves vm2)
3. sign the CSR with server.ext  <-- CSR --
   = teamvks-server.crt          -- cert -->  4. nginx uses cert + key on port 443
5. trust teamvks-ca.crt on every client (VMs + Mac)
```

The exact commands with explanations are in [docs/05-tls.md](../docs/05-tls.md).

## Inspect the certificates

```bash
openssl x509 -in tls/teamvks-ca.crt -noout -subject -issuer -dates -ext basicConstraints,keyUsage
openssl x509 -in tls/teamvks-server.crt -noout -subject -issuer -dates -ext subjectAltName,extendedKeyUsage
openssl verify -CAfile tls/teamvks-ca.crt tls/teamvks-server.crt
openssl x509 -in tls/teamvks-server.crt -noout -fingerprint -sha256
```
