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

ssh_field_last() {
  local machine="$1"
  local field="$2"

  awk -v machine="${machine}" -v field="${field}" '
    $1 == "Host" && $2 == machine { in_host = 1; next }
    $1 == "Host" && $2 != machine { in_host = 0 }
    in_host && $1 == field {
      $1 = ""
      sub(/^[[:space:]]+/, "")
      value = $0
    }
    END {
      if (value != "") {
        print value
      }
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

windows_host_for_wsl() {
  if [[ -n "${SECURE_ACNG_WINDOWS_HOST:-}" ]]; then
    echo "${SECURE_ACNG_WINDOWS_HOST}"
    return 0
  fi

  awk '/^nameserver[[:space:]]+/ { print $2; exit }' /etc/resolv.conf
}

ansible_hostname_for() {
  local hostname="$1"
  echo "${hostname}"
}

windows_tool() {
  local tool="$1"
  local path="/mnt/c/Windows/System32/OpenSSH/${tool}.exe"

  if [[ -x "${path}" ]]; then
    echo "${path}"
  fi
}

key_for_connection() {
  local key="$1"
  local ssh_executable="$2"

  if [[ -n "${SECURE_ACNG_WINDOWS_SSH_KEY:-}" ]]; then
    printf '%s\n' "${SECURE_ACNG_WINDOWS_SSH_KEY}" | tr '\\' '/'
    return 0
  fi

  if [[ -n "${ssh_executable}" && "${key}" =~ ^[A-Za-z]:[/\\] ]]; then
    printf '%s\n' "${key}" | tr '\\' '/'
  else
    path_for_wsl "${key}"
  fi
}

repo_windows_path="$(wslpath -w "${PWD}")"
repo_windows_path_ps="${repo_windows_path//\'/\'\'}"
ssh_config_file="$(mktemp)"
ssh_config_err_file="$(mktemp)"
inventory_file="$(mktemp -p inventory secure-acng-wsl.XXXXXX.yml)"
trap 'rm -f "${ssh_config_file}" "${ssh_config_err_file}" "${inventory_file}"' EXIT

echo "secure-acng: collecting Vagrant SSH configuration from ${repo_windows_path}"

set +e
powershell.exe \
  -NoProfile \
  -NonInteractive \
  -ExecutionPolicy Bypass \
  -Command "\$ErrorActionPreference = 'Stop'; Set-Location -LiteralPath '${repo_windows_path_ps}'; vagrant ssh-config" \
  > "${ssh_config_file}" \
  2> "${ssh_config_err_file}"
ssh_config_status=$?
set -e

tr -d '\r' < "${ssh_config_file}" > "${ssh_config_file}.tmp"
mv "${ssh_config_file}.tmp" "${ssh_config_file}"
tr -d '\r' < "${ssh_config_err_file}" > "${ssh_config_err_file}.tmp"
mv "${ssh_config_err_file}.tmp" "${ssh_config_err_file}"

if [[ "${ssh_config_status}" -ne 0 ]]; then
  echo "secure-acng: vagrant ssh-config failed with exit code ${ssh_config_status}" >&2
  sed 's/^/secure-acng: vagrant ssh-config stderr: /' "${ssh_config_err_file}" >&2
  exit "${ssh_config_status}"
fi

if [[ ! -s "${ssh_config_file}" ]]; then
  echo "secure-acng: vagrant ssh-config returned no hosts" >&2
  sed 's/^/secure-acng: vagrant ssh-config stderr: /' "${ssh_config_err_file}" >&2
  echo "secure-acng: run 'vagrant status' in Windows and make sure all lab VMs are running" >&2
  exit 1
fi

sed 's/^/secure-acng: ssh-config: /' "${ssh_config_file}"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "secure-acng: ansible-playbook was not found in WSL PATH" >&2
  exit 127
fi

{
  ssh_executable="$(windows_tool ssh)"
  scp_executable="$(windows_tool scp)"
  sftp_executable="$(windows_tool sftp)"

  cat <<'EOF'
all:
  vars:
    ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ControlMaster=no -o ControlPath=none -o ControlPersist=no
EOF

  if [[ -n "${ssh_executable}" ]]; then
    cat <<EOF
    ansible_ssh_executable: ${ssh_executable}
EOF
  fi

  if [[ -n "${scp_executable}" ]]; then
    cat <<EOF
    ansible_scp_executable: ${scp_executable}
EOF
  fi

  if [[ -n "${sftp_executable}" ]]; then
    cat <<EOF
    ansible_sftp_executable: ${sftp_executable}
EOF
  fi

  cat <<'EOF'
  children:
    apt_cache_servers:
      hosts:
EOF

  for machine in provcont; do
    host="$(ansible_host_for "${machine}")"
    hostname="$(ansible_hostname_for "$(ssh_field "${machine}" HostName)")"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(key_for_connection "$(ssh_field_last "${machine}" IdentityFile)" "${ssh_executable}")"
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
    hostname="$(ansible_hostname_for "$(ssh_field "${machine}" HostName)")"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(key_for_connection "$(ssh_field_last "${machine}" IdentityFile)" "${ssh_executable}")"
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
    hostname="$(ansible_hostname_for "$(ssh_field "${machine}" HostName)")"
    user="$(ssh_field "${machine}" User)"
    port="$(ssh_field "${machine}" Port)"
    key="$(key_for_connection "$(ssh_field_last "${machine}" IdentityFile)" "${ssh_executable}")"
    cat <<EOF
        ${host}:
          ansible_host: ${hostname}
          ansible_user: ${user}
          ansible_port: ${port}
          ansible_ssh_private_key_file: ${key}
EOF
  done
} > "${inventory_file}"

echo "secure-acng: generated WSL Ansible inventory at ${inventory_file}"
sed 's/^/secure-acng: inventory: /' "${inventory_file}"

echo "secure-acng: checking generated Ansible inventory"
ANSIBLE_CONFIG=./ansible.cfg ansible-inventory -i "${inventory_file}" --graph

echo "secure-acng: running playbooks/site.yml"
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i "${inventory_file}" playbooks/site.yml

if [[ "${SECURE_ACNG_RUN_VALIDATE:-0}" == "1" ]]; then
  echo "secure-acng: running playbooks/validate.yml"
  ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i "${inventory_file}" playbooks/validate.yml
else
  echo "secure-acng: validation skipped; set SECURE_ACNG_RUN_VALIDATE=1 to enable it"
fi
