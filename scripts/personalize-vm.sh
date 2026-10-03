#!/usr/bin/env bash
# Give a cloned lab VM its own identity and a static IP (Task A, steps 6.2-6.4).
#
# Run it on the UTM console, not over SSH (the IP address changes):
#   cd ~/cn && git pull && sudo bash scripts/personalize-vm.sh <vm-name>
#
# <vm-name> is one of: vm1-dns, vm2-edge, vm3-backend-a, vm4-backend-b
# The identity part is skipped when the hostname already matches, so vm1-dns
# (the original install) only gets its static IP, and re-running is safe.
set -euo pipefail

NEW="${1:-}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETPLAN_SRC="$REPO/configs/$NEW/netplan/60-static.yaml"
IFACE=enp0s1
BACKUP_DIR=/root/netplan-backup

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run with sudo"
case "$NEW" in
  vm1-dns|vm2-edge|vm3-backend-a|vm4-backend-b) ;;
  *) die "usage: sudo bash $0 <vm1-dns|vm2-edge|vm3-backend-a|vm4-backend-b>" ;;
esac
[[ -f "$NETPLAN_SRC" ]] || die "missing $NETPLAN_SRC (did you git pull?)"
ip link show "$IFACE" >/dev/null 2>&1 || die "interface $IFACE not found; check: ip -br link"

# --- 1. Identity: hostname, machine-id, SSH host keys -----------------------
if [[ "$(hostname)" == "$NEW" ]]; then
  step "Hostname is already $NEW: keeping machine-id and SSH host keys"
else
  step "Hostname: $(hostname) -> $NEW"
  hostnamectl set-hostname "$NEW"
  if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 $NEW/" /etc/hosts
  else
    echo "127.0.1.1 $NEW" >> /etc/hosts
  fi

  # The DHCP client ID is derived from machine-id, so clones need a fresh one.
  step "New machine-id"
  rm -f /etc/machine-id
  systemd-machine-id-setup

  # Each server must have its own SSH identity.
  step "New SSH host keys"
  rm -f /etc/ssh/ssh_host_*
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure openssh-server
fi

# --- 2. Static IP with netplan ---------------------------------------------
step "Moving the old (DHCP) netplan files to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
shopt -s nullglob
for f in /etc/netplan/*.yaml; do
  if [[ "$(basename "$f")" != 60-static.yaml ]]; then
    mv -v "$f" "$BACKUP_DIR/"
  fi
done

# Stop cloud-init from writing the DHCP config back at boot.
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

install -m 600 "$NETPLAN_SRC" /etc/netplan/60-static.yaml
step "Installed /etc/netplan/60-static.yaml (read it):"
cat /etc/netplan/60-static.yaml

step "netplan try: press ENTER to keep the new config (auto-rollback after 120 s)"
netplan try || die "netplan rolled back; fix the file and run this script again"

# --- 3. Show the result ------------------------------------------------------
step "Result"
echo "hostname   : $(hostname)"
echo "machine-id : $(cat /etc/machine-id)"
ip -br addr show "$IFACE"
ip route | head -1
echo
echo "Expected: $(grep -oE '192\.168\.64\.[0-9]+/24' "$NETPLAN_SRC"), default via 192.168.64.1"
echo "If that matches, finish with: sudo reboot"
