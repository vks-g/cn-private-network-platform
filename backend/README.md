# Backend (Task C)

One small Python program, [`server.py`](server.py), runs as two instances:

| Instance | VM | IP:port | Started with |
| --- | --- | --- | --- |
| Backend A | `vm3-backend-a` | `192.168.64.13:3001` | `--id A --port 3001` |
| Backend B | `vm4-backend-b` | `192.168.64.14:3002` | `--id B --port 3002` |

It uses only the Python standard library (Ubuntu already ships `python3`), so there is nothing to install.

## Endpoints

| Request | Response |
| --- | --- |
| `GET /` | small HTML page: backend id, host, the TCP peer and the original client (`X-Forwarded-For`) |
| `GET /api/status` | `{"backend": "A", "status": "ok", "host": "vm3-backend-a"}` |
| anything else | `404` with a JSON error |
| every response | header `X-Backend: A` (or `B`), so repeated requests show which backend answered |

`HEAD` works too (`curl -I`). The server listens on `0.0.0.0` (every interface) so the edge can reach it; binding `127.0.0.1` would make it reachable from the VM itself only.

## Run it by hand

```bash
python3 backend/server.py --id A --port 3001          # Ctrl+C to stop
curl -i http://192.168.64.13:3001/api/status          # from another VM
```

Each request prints one log line, for example:

```text
backend=A peer=192.168.64.12:41822 xff=192.168.64.14 "GET /api/status HTTP/1.1" 200 -
```

`peer` is whoever opened the TCP connection (the nginx edge, once Task D is done) and `xff` is the original client that nginx reports in `X-Forwarded-For`.

## Run it as a service (what the lab uses)

On each backend VM, with the repo cloned at `~/cn`:

```bash
sudo install -D -m 644 ~/cn/backend/server.py /opt/teamvks/backend/server.py
sudo install -m 644 ~/cn/backend/teamvks-backend.service /etc/systemd/system/teamvks-backend.service
sudo install -m 644 ~/cn/configs/$(hostname)/teamvks-backend.env /etc/default/teamvks-backend
sudo systemctl daemon-reload
sudo systemctl enable --now teamvks-backend
systemctl status teamvks-backend --no-pager
```

- [`teamvks-backend.service`](teamvks-backend.service) reads `BACKEND_ID` and `BACKEND_PORT` from `/etc/default/teamvks-backend`: [A](../configs/vm3-backend-a/teamvks-backend.env) · [B](../configs/vm4-backend-b/teamvks-backend.env).
- It runs as an unprivileged throwaway user (`DynamicUser=yes`) and restarts after a crash, but stays down after `systemctl stop`.
- Logs: `journalctl -u teamvks-backend -f`.

The step-by-step version with explanations is [docs/03-backends.md](../docs/03-backends.md).
