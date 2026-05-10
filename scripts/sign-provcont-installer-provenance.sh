#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sign-provcont-installer-provenance.sh [options]

Interactively sign installer provenance artifacts on provcont with the HSM that
provcont sees through USB/IP. Run this from a real operator terminal so GPG
pinentry can prompt for the YubiKey PIN.

Options:
  --project NAME       Artifact project name (default: installer-usb)
  --key KEYID          Signing key or subkey ID (default: 18D3330CFEE8FA61)
  --machine NAME       Vagrant machine name (default: provcont)
  -h, --help           Show this help
EOF
}

project=installer-usb
signing_key=18D3330CFEE8FA61
machine=provcont

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2:?--project requires a value}"
      shift 2
      ;;
    --key)
      signing_key="${2:?--key requires a value}"
      shift 2
      ;;
    --machine)
      machine="${2:?--machine requires a value}"
      shift 2
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
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
infra_dir="$(cd -- "${script_dir}/.." && pwd)"

remote_script="$(mktemp)"
trap 'rm -f "${remote_script}"' EXIT

cat >"${remote_script}" <<'REMOTE'
set -euo pipefail

project="$1"
signing_key="$2"
artifact_dir="/srv/mkosi-artifacts/${project}"
files=(
  SHA256SUMS
  "${project}.manifest.json"
  "${project}.media-issuance.json"
  "${project}.media-write.json"
)

cd "${artifact_dir}"

export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

echo "== USB/IP imports =="
sudo /usr/sbin/usbip port

echo "== GPG card =="
gpg --card-status

echo "== Signing provenance artifacts in ${artifact_dir} =="
for file in "${files[@]}"; do
  test -f "${file}"
  rm -f "${file}.asc"
  gpg --armor --yes --detach-sign \
    --local-user "${signing_key}" \
    --output "${file}.asc" \
    "${file}"
done

echo "== Verifying detached signatures =="
for file in "${files[@]}"; do
  gpg --verify "${file}.asc" "${file}"
done

echo "== Signatures =="
ls -l -- *.asc
REMOTE

cd "${infra_dir}"
vagrant ssh "${machine}" -- -tt "bash -s -- $(printf '%q' "${project}") $(printf '%q' "${signing_key}")" <"${remote_script}"
