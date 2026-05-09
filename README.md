# secure-acng

A Vagrant-backed Ansible lab for testing secure `apt-cacher-ng` operation on Debian Bookworm.

The lab brings up one server and four client VMs:

| VM | IP | Purpose |
| --- | --- | --- |
| `provcont` | `192.168.200.2` | Runs `apt-cacher-ng`, nginx TLS proxying, and aptly |
| `client-http-https-path` | `192.168.200.3` | Tests ACNG `HTTPS///` URLs over HTTP |
| `client-http-proxy` | `192.168.200.7` | Tests formal `Acquire::http::Proxy` mode |
| `client-http-internal-domain` | `192.168.200.5` | Tests clean HTTP URLs through `apt-cache.provcont.lan` |
| `client-https-internal-domain` | `192.168.200.6` | Tests clean HTTPS URLs through `apt-cache.provcont.lan` |

> [!TIP]
> Provcont combines the first 4 letters of `provisioning controller`.

For the underlying secure ACNG patterns, see [Secure-apt-cacher-ng-setup.md](Secure-apt-cacher-ng-setup.md).

## Nested Collection

The Ansible roles for this lab live in the sibling `nested` collection checkout:

```text
../nested/roles/
```

When this repository is used as `mkosi-lab/infra`, the same collection is reached one level farther up:

```text
../../nested/roles/
```

Keep this repository checked out next to `nested`, or use it as the `infra` submodule inside `mkosi-lab` with `nested` checked out alongside `mkosi-lab`. The local `ansible.cfg` points `roles_path` at both locations, so the playbooks can keep using the short role names while the reusable role implementations live in the collection project.

## Requirements

Run this on a Linux host with virtualization support. The lab supports these Vagrant providers:

- `libvirt`, the default path for this repository
- `virtualbox`

The repository includes a helper for common Linux distributions:

```bash
scripts/install-linux-deps.sh
```

It installs Ansible, Vagrant, libvirt/QEMU, `vagrant-libvirt`, SSH, rsync, build tooling, and related dependencies. If it adds your user to `libvirt` or `kvm`, log out and back in before continuing.

For VirtualBox, install VirtualBox for your host OS before starting the lab. The `debian/bookworm64` base box currently publishes both `libvirt` and `virtualbox` provider images.

Useful options:

```bash
scripts/install-linux-deps.sh --skip-vagrant-plugin
scripts/install-linux-deps.sh --no-user-groups
```

## Start The Lab

With libvirt:

```bash
vagrant up --provider=libvirt
ansible-inventory --graph
ansible-playbook playbooks/site.yml
```

With VirtualBox:

```bash
vagrant up --provider=virtualbox
```

On Windows, run Vagrant from PowerShell or Windows Terminal. After the VMs are up, the `Vagrantfile` runs the Ansible site playbook through WSL:

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/run-wsl-ansible.ps1 -RepoPath <repo>
```

The helper asks Windows Vagrant for `vagrant ssh-config`, builds a temporary WSL-friendly Ansible inventory, and connects through Vagrant's forwarded SSH ports. This avoids relying on WSL being able to reach the VirtualBox host-only `192.168.200.x` addresses directly.

To run validation automatically after provisioning:

```powershell
$env:SECURE_ACNG_RUN_VALIDATE = "1"
vagrant up --provider=virtualbox
```

To skip automatic WSL provisioning and run Ansible yourself:

```powershell
$env:SECURE_ACNG_SKIP_WSL_ANSIBLE = "1"
vagrant up --provider=virtualbox
```

Then from WSL:

```bash
ANSIBLE_CONFIG=./ansible.cfg ansible-inventory --graph
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook playbooks/site.yml
```

If the private VirtualBox IPs are not reachable from WSL, use the same helper manually:

```bash
scripts/ansible-site-from-wsl.sh
```

### Windows, VirtualBox, WSL: Why This Is Weird

This path is useful, but it is also the most fragile path in the lab. The moving parts cross three execution contexts:

- Windows Vagrant controls VirtualBox.
- WSL runs Ansible.
- The Debian guests are reached through Vagrant's SSH forwarding.

Several almost-correct approaches fail in surprising ways:

- Running Ansible directly against the private `192.168.200.x` VirtualBox addresses from WSL can fail because WSL may not be on the VirtualBox host-only network.
- Using `127.0.0.1:<vagrant-port>` from WSL can fail because that is WSL localhost, not Windows localhost.
- Asking Windows `ssh.exe` to behave like a Unix SSH client under Ansible can expose oddities around control sockets, transfer helpers, and private-key ACL checks.
- Piping a shell helper into `bash` can break when the helper itself calls `powershell.exe`, because child processes may consume the remaining stdin.
- Windows checkouts may give shell scripts CRLF line endings, which turns `#!/usr/bin/env bash` into `bash\r`.
- A temporary inventory outside `inventory/` will not automatically load this repo's `group_vars` and `host_vars`.
- Vagrant's insecure private keys may have ACLs that Windows OpenSSH refuses, so the wrapper creates a restricted temporary copy.

The current helper exists because of all of that scar tissue. It asks Windows Vagrant for the real SSH config, generates an inventory inside this repo's `inventory/` directory, normalizes paths between Windows and WSL, and keeps enough diagnostics visible to make failures actionable. This setup was harder than it looks, but it is valuable because it lets a Windows user run VirtualBox normally while still using Ansible from WSL.

The `Vagrantfile` creates all five Debian Bookworm machines with static private IPs. For libvirt it uses the shared `mkosi-lab` network. For VirtualBox it uses Vagrant's private-network support directly. The Ansible site playbook configures the cache server, aptly server pieces, and each client mode.

## Validate

Run the validation playbook:

```bash
ansible-playbook playbooks/validate.yml
```

You can also inspect the server directly:

```bash
vagrant ssh provcont
systemctl is-active apt-cacher-ng
systemctl is-active nginx
curl -I http://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I https://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I https://aptly.provcont.lan/
tail -n 100 /var/log/apt-cacher-ng/apt-cacher.log
```

Check a client:

```bash
vagrant ssh client-https-internal-domain
getent hosts apt-cache.provcont.lan
apt-cache policy
sudo apt update
```

## Tear Down

Stop the lab:

```bash
vagrant halt
```

Destroy the VMs:

```bash
vagrant destroy -f
```

## Playbooks

The main entrypoint is:

```bash
ansible-playbook playbooks/site.yml
```

Targeted playbooks are also available:

```bash
ansible-playbook playbooks/apt_cache_server.yml
ansible-playbook playbooks/aptly_server.yml
ansible-playbook playbooks/apt_cache_clients.yml
ansible-playbook playbooks/validate.yml
```
