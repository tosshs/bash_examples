#!/usr/bin/env bash
# k8s-software-install.sh
# AlmaLinux 10.1 — install Kubernetes prereqs + containerd (Docker repo) + kubelet/kubeadm/kubectl
# Install-only: does NOT run kubeadm init/join.

set -euo pipefail

K8S_REPO_FILE="/etc/yum.repos.d/kubernetes.repo"
DOCKER_REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

disable_swap() {
  swapoff -a || true
  if [[ -f /etc/fstab ]]; then
    sed -i.bak -r 's/^(\s*[^#]\S+\s+\S+\s+swap\s+.*)$/# \1/' /etc/fstab
  fi
}

configure_kernel_modules() {
  cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

  modprobe overlay || true
  modprobe br_netfilter || true
}

configure_sysctl() {
  cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system >/dev/null
}

install_base_tools() {
  dnf -y install \
    curl \
    wget \
    tar \
    jq \
    ca-certificates \
    gnupg2 \
    iproute \
    iputils \
    conntrack-tools \
    socat \
    ethtool \
    ebtables \
    util-linux \
    bash-completion
}

install_containerd() {
  echo "Installing containerd.io from Docker repo..."

  # Ensure dnf plugins are present (for config-manager)
  dnf -y install dnf-plugins-core

  # Add Docker repo if not already present
  if ! dnf repolist all 2>/dev/null | grep -qi '^docker-ce-stable'; then
    dnf config-manager --add-repo "${DOCKER_REPO_URL}"
  fi

  dnf -y install containerd.io

  mkdir -p /etc/containerd
  containerd config default >/etc/containerd/config.toml

  # Use systemd cgroups (recommended/expected by kubeadm)
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl enable --now containerd
}

configure_k8s_repo() {
  # Kubernetes upstream repo (pkgs.k8s.io). Adjust version if you want.
  cat >"${K8S_REPO_FILE}" <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF
}

install_k8s_packages() {
  dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes
  systemctl enable kubelet
}

print_versions() {
  echo "=== Installed versions ==="
  echo -n "containerd: "
  containerd --version || true
  echo -n "kubelet: "
  kubelet --version || true
  echo -n "kubeadm: "
  kubeadm version -o short || true
  echo -n "kubectl: "
  kubectl version --client --output=yaml 2>/dev/null | awk '/gitVersion:/{print $2}' || true
}

main() {
  require_root

  echo "[1/7] Disabling swap (now + persistent)..."
  disable_swap

  echo "[2/7] Loading kernel modules..."
  configure_kernel_modules

  echo "[3/7] Applying sysctl settings..."
  configure_sysctl

  echo "[4/7] Installing base tools..."
  install_base_tools

  echo "[5/7] Installing and configuring containerd..."
  install_containerd

  echo "[6/7] Configuring Kubernetes repo..."
  configure_k8s_repo

  echo "[7/7] Installing kubelet/kubeadm/kubectl..."
  install_k8s_packages

  print_versions
  echo "Done. Next steps: kubeadm init (control-plane) / kubeadm join (worker)."
}

main "$@"
