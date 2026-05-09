#!/usr/bin/env bash
set -euo pipefail

network_name="${PROVCONT_LAB_NETWORK:-mkosi-lab}"
bridge_name="${PROVCONT_LAB_BRIDGE:-virbr1}"
host_ip="${PROVCONT_LAB_HOST_IP:-192.168.200.1}"
netmask="${PROVCONT_LAB_NETMASK:-255.255.255.0}"
dhcp_start="${PROVCONT_LAB_DHCP_START:-192.168.200.10}"
dhcp_end="${PROVCONT_LAB_DHCP_END:-192.168.200.254}"
uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
lock_path="/tmp/${network_name}.lock"

exec 9>"${lock_path}"
flock 9

if ! virsh -c "${uri}" net-info "${network_name}" >/dev/null 2>&1; then
  network_xml="$(mktemp)"
  trap 'rm -f "${network_xml}"' EXIT

  cat >"${network_xml}" <<EOF
<network>
  <name>${network_name}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='${bridge_name}' stp='on' delay='0'/>
  <ip address='${host_ip}' netmask='${netmask}'>
    <dhcp>
      <range start='${dhcp_start}' end='${dhcp_end}'/>
    </dhcp>
  </ip>
</network>
EOF

  virsh -c "${uri}" net-define "${network_xml}"
fi

active_state="$(virsh -c "${uri}" net-info "${network_name}" | awk '/^Active:/ { print $2 }')"
if [[ "${active_state}" != "yes" ]]; then
  virsh -c "${uri}" net-start "${network_name}"
fi
