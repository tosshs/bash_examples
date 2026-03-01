#!/usr/bin/env bash
# bootstrap-control-plane.sh
# AlmaLinux 10.1 — persistent hostname + static IP + disable firewalld + disable SELinux
set -euo pipefail

HOSTNAME_FQDN="k8s-control-plane"
IP_ADDR="192.168.85.200/24"   # keep your test subnet here
GW_ADDR="192.168.85.2"        # adjust as needed
DNS_ADDR="192.168.85.2 192.168.85.2 1.1.1.1 8.8.8.8"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

get_default_dev() {
  ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

get_active_connection_for_dev() {
  local dev="$1"
  nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="${dev}" '$2==d{print $1; exit}'
}

get_primary_nm_connection() {
  local dev con
  dev="$(get_default_dev)"
  if [[ -n "${dev}" ]]; then
    con="$(get_active_connection_for_dev "${dev}" || true)"
    if [[ -n "${con}" ]]; then
      echo "${con}"
      return 0
    fi
  fi
  nmcli -t -f NAME con show --active | head -n1
}

disable_firewall() {
  systemctl disable --now firewalld 2>/dev/null || true
}

disable_selinux() {
  if command -v getenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null || true
  fi
  if [[ -f /etc/selinux/config ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  fi
}

set_persistent_hostname() {
  hostnamectl set-hostname "${HOSTNAME_FQDN}"
}

set_static_ip_nmcli() {
  local con="$1"
  if [[ -z "${con}" ]]; then
    echo "ERROR: Could not determine active NetworkManager connection profile." >&2
    echo "Hint: run: nmcli -t -f NAME,DEVICE con show --active" >&2
    exit 1
  fi

  # IMPORTANT FIX: do it in ONE modify call so NM never sees 'manual' without an address
  nmcli con modify "${con}" \
    ipv4.method manual \
    ipv4.addresses "${IP_ADDR}" \
    ipv4.gateway "${GW_ADDR}" \
    ipv4.dns "${DNS_ADDR}" \
    ipv6.method disabled

  nmcli con down "${con}" || true
  nmcli con up "${con}"
}

update_hosts_file() {
  grep -qE '^\s*192\.168\.85\.200\s+k8s-control-plane(\s|$)' /etc/hosts || \
    echo "192.168.85.200 k8s-control-plane" >> /etc/hosts
  grep -qE '^\s*192\.168\.85\.210\s+k8s-worker(\s|$)' /etc/hosts || \
    echo "192.168.85.210 k8s-worker" >> /etc/hosts
}

main() {
  require_root

  echo "[1/4] Disabling firewall and SELinux..."
  disable_firewall
  disable_selinux

  echo "[2/4] Setting hostname to ${HOSTNAME_FQDN}..."
  set_persistent_hostname

  echo "[3/4] Configuring persistent static IP ${IP_ADDR}..."
  local con
  con="$(get_primary_nm_connection)"
  set_static_ip_nmcli "${con}"

  echo "[4/4] Updating /etc/hosts..."
  update_hosts_file

  echo "Done."
  hostnamectl --static || true
  ip -4 addr show || true
  ip route show default || true
}

main "$@"
