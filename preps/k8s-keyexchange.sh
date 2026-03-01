#!/usr/bin/env bash
# k8s-keyexchange.sh
# Generates SSH key (if missing) and installs it on control-plane and worker
# so future SSH access is passwordless.

set -euo pipefail

CONTROL_IP="192.168.85.200"
WORKER_IP="192.168.85.210"
USER="tosshs"

KEY_FILE="${HOME}/.ssh/id_ed25519"

echo "[1/4] Checking for existing SSH key..."

if [[ ! -f "${KEY_FILE}" ]]; then
    echo "No SSH key found. Generating new ed25519 key..."
    ssh-keygen -t ed25519 -f "${KEY_FILE}" -N "" -C "k8s-lab-key"
else
    echo "Existing SSH key found: ${KEY_FILE}"
fi

echo "[2/4] Installing key on control plane (${CONTROL_IP})..."
ssh-copy-id -i "${KEY_FILE}.pub" "${USER}@${CONTROL_IP}"

echo "[3/4] Installing key on worker (${WORKER_IP})..."
ssh-copy-id -i "${KEY_FILE}.pub" "${USER}@${WORKER_IP}"

echo "[4/4] Testing passwordless login..."

ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${CONTROL_IP}" "echo Control-plane OK"
ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${WORKER_IP}" "echo Worker OK"

echo "Key exchange complete. Passwordless SSH is now enabled."
