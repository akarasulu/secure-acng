#!/usr/bin/env bash
set -euo pipefail

machines=(
  provcont
  client-http-https-path
  client-http-proxy
  client-http-internal-domain
  client-https-internal-domain
)

ansible_host_for() {
  local machine="$1"
  echo "${machine//-/_}"
}

ssh_field() {
  local machine="$1"
  local field="$2"

  awk -v machine="${machine}" -v field="${field}" '
    $1 == "Host" && $2 == machine { in_host = 1; next }
    $1 == "Host" && $2 != machine { in_host = 0 }
    in_host && $1 == field {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      print
      exit
    }
  ' "${ssh_config_file}"
}

path_for_wsl() {
  local path="$1"
  path="${path%\"}"
  path="${path#\"}"

  if [[ "${path}" =~ ^[A-Za-z]:[/\\] ]]; then
    wslpath -u "${path}"
  else
    echo "${path}"
  fi
}

repo_windows_path="$(wslpath -w "${PWD}")"
ssh_config_file="$(mktemp)"
inventory_file="$(mktemp)"
trap 'rm -f "${ssh_config_file}" "${inventory_file}"' EXIT

SECURE_ACNG_REPO_WINDOWS_PATH="${repo_windows_path}" powershell.exe \
  -NoProfile \
  -NonInteractive \
  -ExecutionPolicy Bypass \
  -Command '$ErrorActionPreference = "Stop"; Set-Location -LiteralPath $env:SECURE_ACNG_REPO_WINDOWS_PATH; vagrant ssh-config' |
  tr -d '\r' > "${ssh_config_file}"

{
  cat <<'EOF'
all:
  vars:
    ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  children:
    apt_cache_servers:
      hosts:
EOF

  for machine in provcont; do
    host="$(ansible_host_for "${machine}")"
    hostname="$(ssh_field "${machine}" HostName)"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(path_for_wsl "$(ssh_field "${machine}" IdentityFile)")"
    cat <<EOF
        ${host}:
          ansible_host: ${hostname}
          ansible_user: ${user}
          ansible_port: ${port}
          ansible_ssh_private_key_file: ${key}
EOF
  done

  cat <<'EOF'
    aptly_servers:
      hosts:
EOF

  for machine in provcont; do
    host="$(ansible_host_for "${machine}")"
    hostname="$(ssh_field "${machine}" HostName)"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(path_for_wsl "$(ssh_field "${machine}" IdentityFile)")"
    cat <<EOF
        ${host}:
          ansible_host: ${hostname}
          ansible_user: ${user}
          ansible_port: ${port}
          ansible_ssh_private_key_file: ${key}
EOF
  done

  cat <<'EOF'
    apt_cache_clients:
      hosts:
EOF

  for machine in "${machines[@]:1}"; do
    host="$(ansible_host_for "${machine}")"
    hostname="$(ssh_field "${machine}" HostName)"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(path_for_wsl "$(ssh_field "${machine}" IdentityFile)")"
    cat <<EOF
        ${host}:
          ansible_host: ${hostname}
          ansible_user: ${user}
          ansible_port: ${port}
          ansible_ssh_private_key_file: ${key}
EOF
  done
} > "${inventory_file}"

ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i "${inventory_file}" playbooks/site.yml

if [[ "${SECURE_ACNG_RUN_VALIDATE:-0}" == "1" ]]; then
  ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i "${inventory_file}" playbooks/validate.yml
fi
