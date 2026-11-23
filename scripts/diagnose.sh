#!/usr/bin/env bash
# Extension F: find the broken layer for https://<name>/ from a client VM.
#
# Checks the layers in the order a request uses them and stops at the first one
# that fails, with the most likely causes:
#   1 DNS   does the name resolve? (each DNS server + this machine's resolver)
#   2 TCP   does the edge accept a connection on the port?
#   3 TLS   does the handshake work and does the certificate verify for the name?
#   4 HTTP  does the edge return 200, and which edge/backend answered?
#
# Usage (on a client VM):  bash ~/cn/scripts/diagnose.sh [name] [port] [path]
# Exit code: 0 = all layers fine, 1..4 = number of the first broken layer.
set -u
NAME=${1:-app.teamvks.test}
PORT=${2:-443}
URLPATH=${3:-/api/status}
DNS_SERVERS=(192.168.64.11 192.168.64.13)   # primary vm1, backup vm3
EDGES=" 192.168.64.12 192.168.64.13 "       # edge vm2, standby edge vm3

layer() { printf '\n\033[1m[%s] %s\033[0m\n' "$1" "$2"; }
ok()    { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()   { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
warn()  { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
info()  { printf '        %s\n' "$*"; }
stop()  { printf '\n\033[1;31m==> Broken layer: %s\033[0m\n' "$1"; shift
          for h in "$@"; do printf '    - %s\n' "$h"; done; exit "$LAYER"; }

echo "Diagnosing https://$NAME:$PORT$URLPATH from $(hostname)"

# ---- 1. DNS ------------------------------------------------------------------
LAYER=1; layer 1 "DNS (UDP/53): name -> IP"
for s in "${DNS_SERVERS[@]}"; do
    r=$(dig @"$s" +time=2 +tries=1 "$NAME" A 2>&1)
    st=$(grep -o 'status: [A-Z]*' <<<"$r" | cut -d' ' -f2)
    a=$(awk '/ANSWER SECTION/ { f = 1; next } f && $4 == "A" { print $5 " (ttl " $2 ")"; exit }' <<<"$r")
    if [[ -z $st ]]; then warn "server $s: no reply (dnsmasq stopped or host down)"
    elif [[ $st == NOERROR && -n $a ]]; then ok "server $s: $NAME -> $a"
    else warn "server $s: $st, no A record"; fi
done
IP=$(getent ahostsv4 "$NAME" | awk 'NR == 1 { print $1 }')
if [[ -z $IP ]]; then
    bad "this machine's resolver returns no address for $NAME"
    stop "DNS" \
        "every server above says NXDOMAIN -> the record is missing or misspelt (host-record in /etc/dnsmasq.d/teamvks-records.conf)" \
        "every server above has no reply -> dnsmasq stopped on vm1 and vm3 (systemctl status dnsmasq)" \
        "servers answer but this machine doesn't -> wrong resolver config here (resolvectl status, netplan nameservers)"
fi
ok "resolver on $(hostname) (systemd-resolved, cached) -> $IP"
[[ $EDGES == *" $IP "* ]] || warn "$IP is not one of our edges ($EDGES) -> wrong IP in the DNS record?"

# ---- 2. TCP ------------------------------------------------------------------
LAYER=2; layer 2 "TCP: connect to $IP:$PORT"
t0=$(date +%s%N)
err=$(timeout 3 bash -c "exec 3<>/dev/tcp/$IP/$PORT" 2>&1); rc=$?
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
if (( rc == 0 )); then
    ok "three-way handshake completed in ${ms} ms"
else
    if ping -c1 -W1 "$IP" >/dev/null 2>&1; then host="host $IP answers ping (IP layer fine)"; else host="host $IP does not answer ping"; fi
    if (( rc == 124 )); then
        bad "no reply within 3 s (timeout); $host"
        stop "TCP" "packets are dropped: a firewall rule (nft list ruleset), or the IP is wrong / the host is down" \
                   "a timeout is a silent drop; 'connection refused' would mean the host is up but no service"
    elif [[ $err == *refused* ]]; then
        bad "connection refused (TCP RST); $host"
        stop "TCP" "the edge is up but nothing listens on port $PORT: nginx stopped (systemctl status nginx)" \
                   "or nginx listens on another port (ss -ltnp on the edge, 'listen' lines in the nginx config)"
    else
        bad "${err##*: }; $host"
        stop "TCP" "no route to $IP: wrong IP in DNS, or that VM is down"
    fi
fi

# ---- 3. TLS ------------------------------------------------------------------
LAYER=3; layer 3 "TLS: handshake + certificate check for $NAME"
s=$(timeout 5 openssl s_client -connect "$IP:$PORT" -servername "$NAME" -verify_hostname "$NAME" </dev/null 2>&1)
proto=$(grep -m1 -oE 'TLSv1\.[0-3]' <<<"$s")
code=$(sed -n 's/.*Verify return code: \([0-9]*\) (\(.*\))/\1 \2/p' <<<"$s" | tail -1)
cert=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' <<<"$s")
if [[ -z $proto || -z $cert ]]; then
    bad "no TLS handshake on $IP:$PORT"
    stop "TLS" "something answers on port $PORT but does not speak TLS: missing 'ssl' on the listen line, or the wrong service on this port"
fi
info "$(openssl x509 -noout -subject <<<"$cert")   $(openssl x509 -noout -issuer <<<"$cert")"
info "$(openssl x509 -noout -ext subjectAltName <<<"$cert" | tail -1 | sed 's/^ *//')   expires: $(openssl x509 -noout -enddate <<<"$cert" | cut -d= -f2)"
if [[ ${code%% *} == 0 ]]; then
    ok "$proto handshake, certificate verified for $NAME (signed by a trusted CA, name matches, in date)"
else
    bad "$proto handshake, but certificate check failed: ${code#* }"
    stop "TLS" "'self-signed' / 'unable to get local issuer' -> nginx serves a certificate our CA did not sign (ssl_certificate path in the nginx config), or our CA is not trusted on this client" \
               "'hostname mismatch' -> the certificate's SAN does not contain $NAME" \
               "'certificate has expired' / 'not yet valid' -> dates (or a clock problem)"
fi

# ---- 4. HTTP -----------------------------------------------------------------
LAYER=4; layer 4 "HTTP: GET https://$NAME:$PORT$URLPATH"
h=$(curl -sS -o /dev/null -D - -w 'code: %{http_code}\n' --max-time 10 "https://$NAME:$PORT$URLPATH" 2>&1 | tr -d '\r')
code=$(awk '/^code:/ { print $2 }' <<<"$h")
edge=$(awk -F': ' 'tolower($1) == "x-edge" { print $2 }' <<<"$h")
be=$(awk -F': ' 'tolower($1) == "x-backend" { print $2 }' <<<"$h")
case $code in
    200) ok "200 OK   x-edge: ${edge:--}   x-backend: ${be:--}" ;;
    502) bad "502 Bad Gateway from edge ${edge:-?}"
         stop "HTTP (edge -> backend)" "the edge works but no backend answered: both backends stopped, or a wrong IP/port in the nginx upstream block" \
              "look at the edge: sudo tail /var/log/nginx/error.log (connect() failed ... upstream: ...)" ;;
    504) bad "504 Gateway Timeout from edge ${edge:-?}"
         stop "HTTP (edge -> backend)" "a backend accepted no connection in time: a firewall dropping edge -> backend traffic, or a hung backend" ;;
    000|"") bad "no HTTP response: ${h##*curl: }"
         stop "HTTP" "the request failed after TLS: see the curl error above" ;;
    *)   bad "HTTP $code from edge ${edge:-?}, backend ${be:--}"
         stop "HTTP (application)" "404 = no such path/location; 5xx from a backend = application error (journalctl -u teamvks-backend)" ;;
esac

printf '\n\033[1;32m==> All four layers OK: DNS -> TCP -> TLS -> HTTP\033[0m\n'
