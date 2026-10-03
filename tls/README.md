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
