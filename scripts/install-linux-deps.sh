#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install-linux-deps.sh [--skip-vagrant-plugin] [--no-user-groups]

Installs host-side Linux dependencies for this Vagrant + Ansible + libvirt lab.
Also installs Linux USB/IP tooling so this host can export operator USB devices
to provcont when used as an operator workstation.

Options:
  --skip-vagrant-plugin  Do not install/update the vagrant-libvirt plugin
  --no-user-groups       Do not add the current user to libvirt-related groups
  -h, --help             Show this help
EOF
}

skip_vagrant_plugin=false
manage_user_groups=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-vagrant-plugin)
      skip_vagrant_plugin=true
      ;;
    --no-user-groups)
      manage_user_groups=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "${EUID}" -eq 0 ]]; then
  sudo_cmd=()
  target_user="${SUDO_USER:-root}"
else
  sudo_cmd=(sudo)
  target_user="${USER}"
fi

have() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  if have apt-get; then
    "${sudo_cmd[@]}" apt-get update
    "${sudo_cmd[@]}" apt-get install -y \
      ansible \
      bridge-utils \
      build-essential \
      ca-certificates \
      curl \
      libvirt-clients \
      libvirt-daemon-system \
      libvirt-dev \
      openssh-client \
      pkg-config \
      qemu-kvm \
      rsync \
      ruby-dev \
      vagrant
  elif have dnf; then
    "${sudo_cmd[@]}" dnf install -y \
      ansible-core \
      bridge-utils \
      ca-certificates \
      curl \
      gcc \
      libvirt \
      libvirt-daemon-kvm \
      libvirt-devel \
      make \
      openssh-clients \
      pkgconf-pkg-config \
      qemu-kvm \
      rsync \
      ruby-devel \
      vagrant
  elif have pacman; then
    "${sudo_cmd[@]}" pacman -Sy --needed --noconfirm \
      ansible \
      base-devel \
      bridge-utils \
      ca-certificates \
      curl \
      libvirt \
      openssh \
      pkgconf \
      qemu-full \
      rsync \
      ruby \
      vagrant
  elif have zypper; then
    "${sudo_cmd[@]}" zypper --non-interactive install \
      ansible \
      bridge-utils \
      ca-certificates \
      curl \
      gcc \
      libvirt \
      libvirt-devel \
      make \
      openssh \
      pkg-config \
      qemu-kvm \
      rsync \
      ruby-devel \
      vagrant
  else
    echo "Unsupported Linux package manager. Install Ansible, Vagrant, libvirt, QEMU/KVM, Ruby development headers, rsync, and OpenSSH manually." >&2
    exit 1
  fi
}

install_usbip_packages() {
  if have usbip && have usbipd; then
    return 0
  fi

  if have apt-get; then
    "${sudo_cmd[@]}" apt-get install -y usbip
  elif have dnf; then
    "${sudo_cmd[@]}" dnf install -y usbip || "${sudo_cmd[@]}" dnf install -y kernel-tools || true
  elif have pacman; then
    "${sudo_cmd[@]}" pacman -Sy --needed --noconfirm usbip || true
  elif have zypper; then
    "${sudo_cmd[@]}" zypper --non-interactive install usbip || true
  fi

  if ! have usbip || ! have usbipd; then
    echo "WARNING: Linux USB/IP tools were not found after package installation. Install your distribution's usbip package before exporting operator USB devices." >&2
  fi
}

enable_libvirt() {
  if have systemctl; then
    if systemctl list-unit-files libvirtd.service >/dev/null 2>&1; then
      "${sudo_cmd[@]}" systemctl enable --now libvirtd
    elif systemctl list-unit-files virtqemud.service >/dev/null 2>&1; then
      "${sudo_cmd[@]}" systemctl enable --now virtqemud
      "${sudo_cmd[@]}" systemctl enable --now virtnetworkd || true
    fi
  fi
}

enable_usbip() {
  if have modprobe; then
    "${sudo_cmd[@]}" modprobe usbip-core || true
    "${sudo_cmd[@]}" modprobe usbip-host || true
  fi

  if have systemctl; then
    if systemctl list-unit-files usbipd.service >/dev/null 2>&1; then
      "${sudo_cmd[@]}" systemctl enable --now usbipd
    elif have usbipd; then
      echo "usbipd.service was not found; start usbipd manually with 'sudo usbipd -D' before exporting devices."
    fi
  elif have usbipd; then
    echo "systemd was not found; start usbipd manually with 'sudo usbipd -D' before exporting devices."
  fi
}

add_user_groups() {
  [[ "${manage_user_groups}" == true ]] || return 0
  [[ "${target_user}" != "root" ]] || return 0

  for group in libvirt kvm; do
    if getent group "${group}" >/dev/null 2>&1; then
      "${sudo_cmd[@]}" usermod -aG "${group}" "${target_user}"
    fi
  done
}

install_vagrant_plugin() {
  [[ "${skip_vagrant_plugin}" == false ]] || return 0

  if ! have vagrant; then
    echo "vagrant was not found after package installation." >&2
    exit 1
  fi

  if vagrant plugin list | grep -q '^vagrant-libvirt '; then
    vagrant plugin update vagrant-libvirt
  else
    vagrant plugin install vagrant-libvirt
  fi
}

install_packages
install_usbip_packages
enable_libvirt
enable_usbip
add_user_groups
install_vagrant_plugin

cat <<EOF

Host dependency setup complete.

If this script added ${target_user} to libvirt or kvm groups, log out and back in
before running:

  vagrant up
  ansible-playbook playbooks/site.yml

Linux USB/IP tooling was installed for operator USB export. To export a device
from this Linux host, start usbipd if needed, run 'usbip list -l', then bind only
approved devices with 'sudo usbip bind -b <busid>'.
EOF
