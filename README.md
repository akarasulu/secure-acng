# secure-acng

A Vagrant-backed Ansible lab for testing secure `apt-cacher-ng` operation on Debian Bookworm.

The lab brings up one server and four client VMs:

| VM | IP | Purpose |
| --- | --- | --- |
| `provcont` | `192.168.202.2` | Runs `apt-cacher-ng`, nginx TLS proxying, and aptly |
| `client-http-https-path` | `192.168.202.11` | Tests ACNG `HTTPS///` URLs over HTTP |
| `client-http-proxy` | `192.168.202.12` | Tests formal `Acquire::http::Proxy` mode |
| `client-http-internal-domain` | `192.168.202.13` | Tests clean HTTP URLs through `apt-cache.provcont.lan` |
| `client-https-internal-domain` | `192.168.202.14` | Tests clean HTTPS URLs through `apt-cache.provcont.lan` |

For the underlying secure ACNG patterns, see [Secure-apt-cacher-ng-setup.md](Secure-apt-cacher-ng-setup.md).

## Requirements

Run this on a Linux host with virtualization support. The repository includes a helper for common distributions:

```bash
scripts/install-linux-deps.sh
```

It installs Ansible, Vagrant, libvirt/QEMU, `vagrant-libvirt`, SSH, rsync, build tooling, and related dependencies. If it adds your user to `libvirt` or `kvm`, log out and back in before continuing.

Useful options:

```bash
scripts/install-linux-deps.sh --skip-vagrant-plugin
scripts/install-linux-deps.sh --no-user-groups
```

## Start The Lab

From the repository root:

```bash
vagrant up
ansible-inventory --graph
ansible-playbook playbooks/site.yml
```

The `Vagrantfile` creates the shared libvirt network `provcont-lab` and starts all five Debian Bookworm machines. The Ansible site playbook configures the cache server, aptly server pieces, and each client mode.

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

