#!/usr/bin/env bash
# Extensions B and E: watch a DNS record change reach this client.
#
# Every INTERVAL seconds, one line:
#   TIME | the answer and its remaining TTL in THIS machine's DNS cache
#          (systemd-resolved at 127.0.0.53)
#        | the IP curl actually connected to | which edge and which backend answered.
#
# curl only uses that cache when /etc/resolv.conf points at the stub 127.0.0.53
# (Ubuntu's default). Our VMs were switched to query 192.168.64.11 directly in
# Phase 1 (no client cache), so for this demo switch the client to the stub first:
#   sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# and back afterwards:
#   sudo ln -sf ../run/systemd/resolve/resolv.conf /etc/resolv.conf
#
# While the cached answer is still valid the client keeps going to the old edge,
# even though the DNS server already has the new record. When the TTL runs out,
# the next lookup fetches the new record and traffic moves to the new edge.
#
# Usage (on a client VM):  bash ~/cn/scripts/watch-cutover.sh [name] [count] [interval]
set -u
NAME=${1:-app.teamvks.test}
COUNT=${2:-12}
INTERVAL=${3:-5}

printf '%-8s  %-28s  %-14s  %-14s  %s\n' TIME "CACHED ANSWER (IP, TTL left)" CONNECTED-TO X-EDGE X-BACKEND
for ((i = 1; i <= COUNT; i++)); do
    # Ask the local cache (not the DNS server directly): this is what applications see.
    ans=$(dig @127.0.0.53 +noall +answer "$NAME" A | awk '$4 == "A" { print $5 ", ttl " $2 "s"; exit }')
    out=$(curl -sS -o /dev/null -D - -w 'remote-ip: %{remote_ip}\n' --max-time 5 \
          "https://$NAME/api/status" 2>&1 | tr -d '\r')
    ip=$(awk -F': ' 'tolower($1) == "remote-ip" { print $2 }' <<<"$out")
    edge=$(awk -F': ' 'tolower($1) == "x-edge" { print $2 }' <<<"$out")
    be=$(awk -F': ' 'tolower($1) == "x-backend" { print $2 }' <<<"$out")
    printf '%-8s  %-28s  %-14s  %-14s  %s\n' "$(date +%T)" "${ans:-no answer}" "${ip:--}" "${edge:--}" "${be:--}"
    ((i < COUNT)) && sleep "$INTERVAL"
done
