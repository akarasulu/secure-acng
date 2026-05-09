# AGENTS.md

## Mission

Build this repository into a Vagrant-backed Ansible lab for secure `apt-cacher-ng` operation.

The implementation must use the information in [Secure-apt-cacher-ng-setup.md](Secure-apt-cacher-ng-setup.md) as the behavioral source of truth, with one lab-specific adjustment: the nginx HTTP listener must proxy to apt-cacher-ng instead of redirecting, so the HTTP internal-domain client can be tested concurrently with HTTPS clients. The target system is a Debian Bookworm `provcont` machine that runs:

- `apt-cacher-ng`
- `nginx` as a reverse proxy
- TLS termination for `apt-cache.provcont.lan`
- HTTPS upstream repository fetching through apt-cacher-ng backend files and remap rules
- `aptly`

Final repository flow:

```text
apt-cacher-ng = lazy transport/package cache
aptly         = repository manager, mirror, snapshot, publisher
```

The final mirror/update flow should be:

```text
aptly mirror update
  -> fetches upstream packages through apt-cacher-ng
  -> apt-cacher-ng fetches from Debian over HTTPS and caches objects
  -> aptly stores the mirrored packages in its own pool
  -> aptly snapshots/publishes from its own storage
```

Aptly mirror URLs should use normal HTTP Debian URLs while the aptly command environment points `http_proxy` at apt-cacher-ng. The apt-cacher-ng host-style remaps then force the Internet leg to HTTPS. Do not configure aptly to bypass apt-cacher-ng for Debian mirror updates.

Client progression:

```text
Phase 1: clients test apt-cacher-ng directly through the four cache modes
Phase 2: aptly mirrors Debian through apt-cacher-ng
Phase 3: aptly snapshots/publishes signed repositories
Phase 4: clients move from apt-cacher-ng URLs to aptly published URLs
```

Do not switch clients to aptly repositories until aptly publishing and repository signing are configured. Do not use `trusted=yes` as a shortcut.

The reusable Ansible roles for this lab live in the sibling `nested` Ansible collection checkout. Use `../nested/roles` when this repository is checked out directly beside `nested`, and `../../nested/roles` when this repository is used as `mkosi-lab/infra`. Keep roles general-purpose and variable-driven. Avoid hard-coding the lab name except in inventory/group vars/defaults.

Important target: `provcont` must have one apt-cacher-ng configuration and one apt-cache nginx reverse proxy configuration that support all client scenarios at the same time. Do not reconfigure, reset, switch, or toggle the server between client tests. The clients vary; the server stays stable.

## Current Baseline

The current `Vagrantfile` defines one Debian Bookworm machine:

- Name: `provcont`
- Hostname: `provcont`
- Private IP: `192.168.200.2`
- Libvirt network: `mkosi-lab`
- Host IP: `192.168.200.1`
- DHCP range: `192.168.200.10` through `192.168.200.254`

The initial cache DNS name is:

- `apt-cache.provcont.lan`

This hostname must be parameterized in Ansible variables.

## Required Repository Layout

Create this structure at the repository root:

```text
scripts/
  install-linux-deps.sh
ansible.cfg
inventory/
  hosts.yml
  group_vars/
    all.yml
    apt_cache_servers.yml
    apt_cache_clients.yml
  host_vars/
    provcont.yml
playbooks/
  site.yml
  apt_cache_server.yml
  apt_cache_clients.yml
  aptly_server.yml
  validate.yml
../nested/roles/
  apt_cacher_ng/
  nginx_acng_reverse_proxy/
  aptly_server/
  apt_cache_client/
```

Role internals should follow normal Ansible role layout:

```text
defaults/main.yml
tasks/main.yml
handlers/main.yml
templates/
files/
meta/main.yml
README.md
```

Add role READMEs that document variables, supported modes, and example usage.

## Host Dependency Bootstrap

Provide a host-side Linux dependency installer at:

```text
scripts/install-linux-deps.sh
```

This script prepares the operator workstation, not the Vagrant guests. It may use shell because Ansible, Vagrant, libvirt, and the Vagrant libvirt provider may not exist yet.

The script must be idempotent where practical and should support common Linux package managers:

- `apt-get`
- `dnf`
- `pacman`
- `zypper`

It should install the host dependencies needed to run the lab:

- Ansible
- Vagrant
- `vagrant-libvirt`
- libvirt client and daemon packages
- QEMU/KVM
- Ruby development headers and build tooling needed by Vagrant plugins
- OpenSSH client
- rsync
- CA certificates and curl

It should also:

- enable the relevant libvirt service when systemd is available
- add the current non-root user to `libvirt` and `kvm` groups when those groups exist
- print a reminder to log out and back in after group membership changes
- support `--skip-vagrant-plugin`
- support `--no-user-groups`

Do not use this script to configure guest machines. Guest configuration belongs in Ansible roles.

## Ansible Configuration

Create `ansible.cfg` in the repo root with repository-local defaults:

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = ../nested/roles:../../nested/roles
host_key_checking = False
retry_files_enabled = False
stdout_callback = default
interpreter_python = auto_silent

[ssh_connection]
pipelining = True
```

If the installed Ansible version does not support `stdout_callback = yaml` without extra collections, use a built-in callback instead and document the choice.

## Inventory

Create `inventory/hosts.yml` with at least these groups:

```yaml
all:
  children:
    apt_cache_servers:
      hosts:
        provcont:
          ansible_host: 192.168.200.2
    aptly_servers:
      hosts:
        provcont:
          ansible_host: 192.168.200.2
    apt_cache_clients:
      hosts:
        client_http_https_path:
        client_http_proxy:
        client_http_internal_domain:
        client_https_internal_domain:
```

Set the real client IP addresses after updating `Vagrantfile`.

Use `group_vars/all.yml` for common lab defaults:

```yaml
apt_cache_domain: apt-cache.provcont.lan
aptly_domain: aptly.provcont.lan
apt_cache_server_ip: 192.168.200.2
aptly_server_ip: 192.168.200.2
apt_cache_tls_dir: /etc/ssl/provcont
apt_cache_tls_cert_path: /etc/ssl/provcont/apt-cache.crt
apt_cache_tls_key_path: /etc/ssl/provcont/apt-cache.key
aptly_tls_cert_path: /etc/ssl/provcont/aptly.crt
aptly_tls_key_path: /etc/ssl/provcont/aptly.key
debian_release: bookworm
debian_components:
  - main
  - contrib
  - non-free-firmware
apt_cache_enable_source_repos: false
```

## Vagrant Requirements

Convert `Vagrantfile` into a multi-machine configuration.

Keep `provcont` as the server:

- `provcont`: `192.168.200.2`

Add Debian Bookworm clients for the major access patterns from `Secure-apt-cacher-ng-setup.md`:

- `client-http-https-path`: tests plain HTTP client URLs using `HTTPS///`
- `client-http-proxy`: tests formal `Acquire::http::Proxy` mode with normal HTTP Debian sources
- `client-http-internal-domain`: tests plain HTTP URLs against `apt-cache.provcont.lan` using clean paths and ACNG remaps
- `client-https-internal-domain`: tests HTTPS URLs against `apt-cache.provcont.lan` using clean paths and ACNG remaps

Recommended static private IPs:

```text
provcont                    192.168.200.2
client-http-https-path      192.168.200.3
client-http-proxy           192.168.200.4
client-http-internal-domain 192.168.200.5
client-https-internal-domain 192.168.200.6
```

Each machine should:

- use `debian/bookworm64`
- disable the synced folder unless needed
- keep `m.ssh.insert_key = false`
- share the same private libvirt network
- have a stable hostname matching its machine name, using hyphens

Ensure clients can resolve `apt-cache.provcont.lan`. For the lab, it is acceptable to manage `/etc/hosts` with Ansible. Keep DNS/hosts behavior parameterized.

Each client host exists to test exactly one client mode. Do not stack multiple modes onto the same VM during normal validation, because APT proxy state and source-list state can mask mistakes between modes.

All client hosts must test the same running `provcont` server concurrently. Server-side apt-cacher-ng and nginx settings must not vary by client host.

## Role: `apt_cacher_ng`

Purpose: install and configure apt-cacher-ng in a reusable way.

Responsibilities:

- install `apt-cacher-ng`, `ca-certificates`, and useful diagnostics such as `curl`
- ensure CA certificates are up to date
- configure apt-cacher-ng base settings
- bind apt-cacher-ng so direct private-network clients can reach port `3142`
- create HTTPS backend files
- create remap rules
- optionally enable strict `ForceManaged`
- restart/enable the service when configuration changes

The role must create one apt-cacher-ng configuration that supports every required client scenario concurrently:

- direct `HTTPS///` path clients using `http://192.168.200.2:3142/HTTPS///...`
- formal APT proxy clients using normal HTTP Debian repository URLs and `http://192.168.200.2:3142`
- clean internal HTTP clients using `http://apt-cache.provcont.lan/debian`
- clean internal HTTPS clients using `https://apt-cache.provcont.lan/debian`

Do not create separate apt-cacher-ng configurations per client type. Do not require a server-side playbook rerun with different variables to switch test modes.

Because direct `:3142` clients and formal proxy clients are part of the same test matrix, the lab default must expose apt-cacher-ng on the private Vagrant network. Nginx still handles the internal-domain HTTP and HTTPS client paths.

Default behavior for this lab:

```text
Port: 3142
BindAddress: 0.0.0.0
ForceManaged: disabled by default
```

Required default variables:

```yaml
apt_cacher_ng_port: 3142
apt_cacher_ng_bind_address: 0.0.0.0
apt_cacher_ng_force_managed: false
apt_cacher_ng_config_dir: /etc/apt-cacher-ng
apt_cacher_ng_cache_dir: /var/cache/apt-cacher-ng
apt_cacher_ng_allow_user_ports:
  - 80
  - 443
apt_cacher_ng_backends:
  debian_https:
    file: backends_debian_https
    urls:
      - https://deb.debian.org/debian/
  debian_security_https:
    file: backends_debian_security_https
    urls:
      - https://security.debian.org/debian-security/
apt_cacher_ng_remaps:
  - name: debian-https
    source: /debian
    backend_file: backends_debian_https
  - name: debian-security-https
    source: /debian-security
    backend_file: backends_debian_security_https
  - name: debian-host-https
    source: deb.debian.org/debian
    backend_file: backends_debian_https
  - name: debian-security-host-https
    source: security.debian.org/debian-security
    backend_file: backends_debian_security_https
```

The host-style remaps support formal APT proxy mode:

```text
http://deb.debian.org/debian/... -> https://deb.debian.org/debian/...
http://security.debian.org/debian-security/... -> https://security.debian.org/debian-security/...
```

The path-style remaps support clean internal URLs:

```text
/debian/... -> https://deb.debian.org/debian/...
/debian-security/... -> https://security.debian.org/debian-security/...
```

The `HTTPS///` clients do not need dedicated remap rules; apt-cacher-ng handles that syntax itself. The same server configuration must still allow those requests while also supporting the remap-based modes.

Do not configure `PassThroughPattern` as the primary solution. CONNECT tunneling does not provide useful package-object caching and is intentionally not the goal.

## Role: `nginx_acng_reverse_proxy`

Purpose: expose apt-cacher-ng through nginx, including TLS termination.

Responsibilities:

- install `nginx`
- create or install TLS material for `apt_cache_domain`
- configure HTTP listener on port 80
- configure HTTPS listener on port 443
- proxy all requests to `http://127.0.0.1:3142`
- preserve request path exactly
- set appropriate proxy headers
- enable and reload nginx

The role must create one nginx site for `apt-cache.provcont.lan` that supports the reverse-proxy client scenarios concurrently. Do not swap nginx site templates or listener behavior per client type.

The nginx template must implement the shared lab behavior derived from `Secure-apt-cacher-ng-setup.md`:

```nginx
server {
    listen 80;
    server_name apt-cache.provcont.lan;

    location / {
        proxy_pass http://127.0.0.1:3142;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}

server {
    listen 443 ssl http2;
    server_name apt-cache.provcont.lan;

    ssl_certificate     /etc/ssl/provcont/apt-cache.crt;
    ssl_certificate_key /etc/ssl/provcont/apt-cache.key;

    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:3142;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
```

Parameterize all lab-specific values:

```yaml
nginx_acng_server_name: "{{ apt_cache_domain }}"
nginx_acng_listen_http: 80
nginx_acng_listen_https: 443
nginx_acng_backend_url: "http://127.0.0.1:{{ apt_cacher_ng_port | default(3142) }}"
nginx_acng_tls_cert_path: "{{ apt_cache_tls_cert_path }}"
nginx_acng_tls_key_path: "{{ apt_cache_tls_key_path }}"
```

The apt-cache nginx site must always proxy both HTTP and HTTPS to apt-cacher-ng in this lab, so HTTP and HTTPS clients can run against the same server at the same time:

```text
http://apt-cache.provcont.lan/*  -> http://127.0.0.1:3142/*
https://apt-cache.provcont.lan/* -> http://127.0.0.1:3142/*
```

Do not implement an HTTP-to-HTTPS redirect for `apt-cache.provcont.lan` in this lab. It would collapse the HTTP internal-domain test into the HTTPS path and hide whether the shared server configuration truly handles both protocols.

### Lab TLS and certificate model

The lab must support real TLS validation rather than disabling certificate checks. Generate a local lab CA on the server side, use that CA to sign service certificates, and install the CA certificate on managed clients.

Default generated material:

```yaml
apt_cache_tls_dir: /etc/ssl/provcont
apt_cache_ca_cert_path: /etc/ssl/provcont/provcont-ca.crt
apt_cache_ca_key_path: /etc/ssl/provcont/provcont-ca.key
apt_cache_tls_cert_path: /etc/ssl/provcont/apt-cache.crt
apt_cache_tls_key_path: /etc/ssl/provcont/apt-cache.key
aptly_tls_cert_path: /etc/ssl/provcont/aptly.crt
aptly_tls_key_path: /etc/ssl/provcont/aptly.key
```

The apt-cache certificate must include SAN entries for `apt_cache_domain` and `apt_cache_server_ip`. The aptly certificate must include SAN entries for `aptly_domain` and `aptly_server_ip`.

Private keys must be generated on target hosts with restrictive permissions such as `0600`. Do not commit private keys. Do not set `trusted=yes` in apt sources and do not disable TLS verification to make HTTPS clients pass.

For lab TLS, either:

- generate a local CA and server certificate with Ansible, then install the CA on clients, or
- use checked-in test certificates only if they are clearly marked as disposable lab material.

Prefer generating lab certificates idempotently on `provcont`. Never commit private production keys.

Later production or shared-lab deployments should be able to replace generated material with existing certificates. Model that behind variables instead of hard-coding the lab CA workflow:

```yaml
apt_cache_tls_manage: true
apt_cache_ca_cert_source: null
apt_cache_tls_cert_source: null
apt_cache_tls_key_source: null

aptly_tls_manage: true
aptly_ca_cert_source: null
aptly_tls_cert_source: null
aptly_tls_key_source: null
```

When `*_tls_manage` is false or source files are provided, the role should install the supplied CA, certificate, and key instead of generating new material. If the certificate is issued by a public CA already trusted by clients, client CA installation can be disabled. If an internal CA is used, clients must install that CA certificate through Ansible.

## Role: `apt_cache_client`

Purpose: configure Debian clients to use the cache in several test modes.

Responsibilities:

- install `ca-certificates` and `curl`
- optionally manage `/etc/hosts`
- optionally install the lab CA certificate
- manage `/etc/apt/sources.list`
- manage apt proxy config in `/etc/apt/apt.conf.d/`
- remove or disable conflicting proxy files created by this role if a client host variable is changed and the role is reapplied
- run `apt update` when requested

Supported modes:

```yaml
apt_cache_client_mode: http_https_path
apt_cache_client_mode: http_proxy
apt_cache_client_mode: http_internal_domain
apt_cache_client_mode: https_internal_domain
```

Each mode must be assigned to one dedicated Vagrant client host for integration testing:

```yaml
client_http_https_path:
  apt_cache_client_mode: http_https_path
  apt_cache_client_test_package: sl

client_http_proxy:
  apt_cache_client_mode: http_proxy
  apt_cache_client_test_package: cowsay

client_http_internal_domain:
  apt_cache_client_mode: http_internal_domain
  apt_cache_client_test_package: toilet

client_https_internal_domain:
  apt_cache_client_mode: https_internal_domain
  apt_cache_client_test_package: figlet
```

The exact package names may be changed with variables, but each test client must use a different package by default. Use small packages that are safe to install repeatedly and likely to exist in Debian Bookworm.

Mode behavior:

1. `http_https_path`

   Client source URLs use apt-cacher-ng `HTTPS///` syntax over plain HTTP:

   ```text
   deb http://192.168.200.2:3142/HTTPS///deb.debian.org/debian bookworm main contrib non-free-firmware
   deb http://192.168.200.2:3142/HTTPS///security.debian.org/debian-security bookworm-security main contrib non-free-firmware
   ```

   Do not configure `Acquire::http::Proxy` in this mode.

2. `http_proxy`

   Client source URLs stay normal HTTP Debian URLs:

   ```text
   deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
   deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
   ```

   Configure:

   ```conf
   Acquire::http::Proxy "http://192.168.200.2:3142";
   Acquire::https::Proxy "DIRECT";
   ```

3. `http_internal_domain`

   Client source URLs use clean internal HTTP repository paths:

   ```text
   deb http://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
   deb http://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
   ```

   Do not configure a formal APT proxy.

   This mode must work against the same shared server configuration as the HTTPS client. The lab nginx site must proxy HTTP requests directly to apt-cacher-ng instead of redirecting them to HTTPS, otherwise this mode no longer proves a true HTTP client path.

4. `https_internal_domain`

   Client source URLs use clean internal HTTPS repository paths:

   ```text
   deb https://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
   deb https://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
   ```

   Do not configure a formal APT proxy.

   This is the final recommended shape.

Sources must include:

- `bookworm`
- `bookworm-updates`
- `bookworm-security`
- `bookworm-backports`

Source repositories (`deb-src`) must be optional and disabled by default.

Client cache validation responsibilities:

- optionally remove the selected test package before validation
- install the mode-specific `apt_cache_client_test_package`
- record the package name in a host fact or test result file
- provide enough output for the server-side validation play to confirm cache activity

Prefer Ansible modules:

```yaml
- name: Install cache validation package
  ansible.builtin.apt:
    name: "{{ apt_cache_client_test_package }}"
    state: present
    update_cache: true
```

Do not use the same package on every client. If all clients request the same package, the first successful mode can hide failures in later modes by warming the cache.

Client role variables must affect only client-side configuration. They must not mutate server-side apt-cacher-ng or nginx behavior.

## Role: `aptly_server`

Purpose: install and initialize an aptly server on `provcont` in a reusable way, exposed through nginx at `aptly.provcont.lan` by default.

Responsibilities:

- install `aptly`
- install supporting packages such as `gnupg`, `gpg`, `curl`, and `ca-certificates`
- create an aptly service user if configured
- create aptly root directories
- manage aptly configuration
- configure nginx as a reverse proxy or static publisher for aptly
- expose aptly at `aptly.provcont.lan` by default
- parameterize the aptly domain and TLS paths
- keep aptly nginx configuration separate from the apt-cacher-ng nginx site
- configure aptly mirror definitions that pull through apt-cacher-ng
- provide an aptly command wrapper that exports the apt-cacher-ng proxy environment
- optionally run `aptly mirror update` through apt-cacher-ng when explicitly enabled

Required defaults:

```yaml
aptly_user: aptly
aptly_group: aptly
aptly_root_dir: /var/lib/aptly
aptly_config_path: /etc/aptly.conf
aptly_domain: aptly.provcont.lan
aptly_server_ip: 192.168.200.2
aptly_listen_http: 80
aptly_listen_https: 443
aptly_tls_enabled: true
aptly_tls_cert_path: /etc/ssl/provcont/aptly.crt
aptly_tls_key_path: /etc/ssl/provcont/aptly.key
aptly_nginx_site_name: aptly
aptly_public_dir: /var/lib/aptly/public
aptly_api_enabled: false
aptly_api_listen_host: 127.0.0.1
aptly_api_listen_port: 8080
aptly_acng_proxy_url: http://127.0.0.1:3142
aptly_manage_mirrors: true
aptly_update_mirrors: false
aptly_mirror_architectures:
  - amd64
aptly_mirror_with_sources: false
aptly_mirrors:
  - name: debian-bookworm
    url: http://deb.debian.org/debian
    distribution: bookworm
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-bookworm-updates
    url: http://deb.debian.org/debian
    distribution: bookworm-updates
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-bookworm-backports
    url: http://deb.debian.org/debian
    distribution: bookworm-backports
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-bookworm-security
    url: http://security.debian.org/debian-security
    distribution: bookworm-security
    components:
      - updates/main
      - updates/contrib
      - updates/non-free-firmware
  - name: debian-trixie
    url: http://deb.debian.org/debian
    distribution: trixie
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-trixie-updates
    url: http://deb.debian.org/debian
    distribution: trixie-updates
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-trixie-backports
    url: http://deb.debian.org/debian
    distribution: trixie-backports
    components:
      - main
      - contrib
      - non-free-firmware
  - name: debian-trixie-security
    url: http://security.debian.org/debian-security
    distribution: trixie-security
    components:
      - updates/main
      - updates/contrib
      - updates/non-free-firmware
aptly_download_concurrency: 4
aptly_dependency_follow_suggests: false
aptly_dependency_follow_recommends: false
aptly_dependency_follow_all_variants: false
aptly_dependency_follow_source: false
```

The role should install the package from Debian repositories first. If a newer upstream aptly package source is later needed, add it behind explicit variables.

Aptly must use apt-cacher-ng for mirror transport. The implementation should create an executable wrapper, for example `/usr/local/bin/aptly-acng`, that runs:

```text
http_proxy=http://127.0.0.1:3142
HTTP_PROXY=http://127.0.0.1:3142
aptly -config=/etc/aptly.conf ...
```

Mirror URLs should remain HTTP URLs such as `http://deb.debian.org/debian` and `http://security.debian.org/debian-security`. Apt-cacher-ng remaps those host-style HTTP requests to HTTPS upstreams, so the Internet leg remains HTTPS while aptly benefits from the cache.

The default `aptly_acng_proxy_url` assumes aptly and apt-cacher-ng are on the same host. In a split-host topology, override it with the cache host endpoint, for example:

```yaml
aptly_acng_proxy_url: http://apt-cache.provcont.lan:3142
```

Do not default to `aptly mirror update` during every playbook run; Debian mirrors can be large. Gate mirror updates behind `aptly_update_mirrors: true`, and make the update command use the apt-cacher-ng proxy environment.

By default, aptly mirrors binary packages for the configured architectures only. Set `aptly_mirror_with_sources: true` to include Debian source packages as well. Source mirrors are intentionally opt-in because they make the mirror substantially larger.

The first implementation should create aptly mirror definitions and the ACNG-backed wrapper. Snapshot, signing, and publish automation can be added next, but the design must keep this final client target in mind:

```text
APT clients
  -> https://aptly.provcont.lan/...
  -> nginx serves aptly-published repository content
  -> aptly content was mirrored through apt-cacher-ng
  -> apt-cacher-ng fetched Debian upstreams over HTTPS
```

Default nginx behavior should serve published aptly repositories from `aptly_public_dir`:

```nginx
server {
    listen 80;
    server_name aptly.provcont.lan;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name aptly.provcont.lan;

    ssl_certificate     /etc/ssl/provcont/aptly.crt;
    ssl_certificate_key /etc/ssl/provcont/aptly.key;

    root /var/lib/aptly/public;
    autoindex on;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

If `aptly_api_enabled: true`, add a separate nginx location for the aptly API proxying to `http://127.0.0.1:8080`, but keep that disabled by default. Static repository publishing is the first target.

The `aptly_server` role may install nginx if needed, but it must not overwrite the apt-cacher-ng nginx site. Multiple nginx sites should coexist under `sites-available` and `sites-enabled`.

## Split-Host Topologies

The roles should remain reusable independently. The lab default runs apt-cacher-ng and aptly on `provcont`, but the inventory may split them across hosts:

```yaml
apt_cache_servers:
  hosts:
    acng01:
      ansible_host: 192.168.200.2

aptly_servers:
  hosts:
    aptly01:
      ansible_host: 192.168.200.7
```

In that topology:

```yaml
apt_cache_domain: apt-cache.provcont.lan
apt_cache_server_ip: 192.168.200.2
aptly_domain: aptly.provcont.lan
aptly_server_ip: 192.168.200.7
aptly_acng_proxy_url: http://apt-cache.provcont.lan:3142
```

Keep DNS or managed `/etc/hosts` entries aligned with those two IPs. The cache host must run `apt_cacher_ng` and `nginx_acng_reverse_proxy`; the aptly host must run `aptly_server`.

Certificate handling needs one deliberate choice in split-host deployments:

- use one shared internal CA for both hosts and install that CA on every client
- use separate internal CAs and extend client trust installation to install both CA certificates
- use publicly trusted certificates for one or both HTTPS endpoints

For the current lab, the shared generated CA is acceptable because both services are co-located. If services move to separate hosts while keeping a shared lab CA, distribute the CA/key securely or replace the generated CA with an existing CA source. Do not copy private CA keys to clients.

## Playbooks

Create `playbooks/site.yml`:

```yaml
- import_playbook: apt_cache_server.yml
- import_playbook: aptly_server.yml
- import_playbook: apt_cache_clients.yml
```

Create `playbooks/apt_cache_server.yml`:

```yaml
- hosts: apt_cache_servers
  become: true
  roles:
    - role: apt_cacher_ng
    - role: nginx_acng_reverse_proxy
```

Create `playbooks/aptly_server.yml`:

```yaml
- hosts: aptly_servers
  become: true
  roles:
    - role: aptly_server
```

Create `playbooks/apt_cache_clients.yml`:

```yaml
- hosts: apt_cache_clients
  become: true
  roles:
    - role: apt_cache_client
```

## Client Host Variables

Configure client modes in `inventory/host_vars/`:

```yaml
# inventory/host_vars/client_http_https_path.yml
apt_cache_client_mode: http_https_path
apt_cache_client_test_package: sl

# inventory/host_vars/client_http_proxy.yml
apt_cache_client_mode: http_proxy
apt_cache_client_test_package: cowsay

# inventory/host_vars/client_http_internal_domain.yml
apt_cache_client_mode: http_internal_domain
apt_cache_client_test_package: toilet

# inventory/host_vars/client_https_internal_domain.yml
apt_cache_client_mode: https_internal_domain
apt_cache_client_test_package: figlet
```

Use Ansible inventory hostnames with underscores if needed, while keeping Vagrant machine names and OS hostnames hyphenated.

## Validation

After implementation, these commands should work from the repo root:

```bash
scripts/install-linux-deps.sh
vagrant up
ansible-inventory --graph
ansible-playbook playbooks/site.yml
```

Server checks on `provcont`:

```bash
systemctl is-active apt-cacher-ng
systemctl is-active nginx
systemctl is-active aptly || true
curl -I http://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I http://apt-cache.provcont.lan/debian-security/dists/bookworm-security/InRelease
curl -I http://127.0.0.1:3142/debian/dists/bookworm/InRelease
curl -I http://127.0.0.1:3142/debian-security/dists/bookworm-security/InRelease
curl -I https://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I https://apt-cache.provcont.lan/debian-security/dists/bookworm-security/InRelease
curl -I https://aptly.provcont.lan/
```

Client checks on every client:

```bash
getent hosts apt-cache.provcont.lan
apt-cache policy
apt update
apt-cache policy sl
```

Cache verification on `provcont` after client updates:

```bash
tail -n 100 /var/log/apt-cacher-ng/apt-cacher.log
tail -n 100 /var/log/apt-cacher-ng/apt-cacher.err
find /var/cache/apt-cacher-ng -maxdepth 5 -type f | head -100
```

Package-cache validation should prove that each client mode caused a distinct package request to pass through apt-cacher-ng. Use one package per mode:

```text
http_https_path        sl
http_proxy             cowsay
http_internal_domain   toilet
https_internal_domain  figlet
```

Implement a validation playbook or tagged validation tasks that:

- clear only the selected package from the client before the test when practical
- install the client-specific package using `ansible.builtin.apt`
- inspect apt-cacher-ng logs on `provcont` for that package name or expected package path
- inspect `/var/cache/apt-cacher-ng` for cached files related to that package
- fail if a client completes without evidence that its package request reached the cache

Prefer Ansible `find`, `slurp`, `stat`, `uri`, and registered task results for validation. Use `command` only for read-only diagnostics where no module fits, and set `changed_when: false`.

Expected outcome:

- clients complete `apt update`
- each client installs its own distinct validation package
- all client modes run in the same `vagrant up` environment against one unchanged `provcont` server configuration
- apt-cacher-ng logs show Debian package index requests
- apt-cacher-ng logs or cache files show each distinct validation package request
- cache files appear under `/var/cache/apt-cacher-ng`
- upstream Debian fetches use HTTPS through backend/remap configuration
- HTTPS client mode validates the lab CA and does not require disabling TLS verification
- `https://aptly.provcont.lan/` is served by nginx without interfering with `https://apt-cache.provcont.lan/`

## Implementation Rules

- Keep roles reusable and variable-driven.
- Keep lab defaults in inventory, not buried in tasks.
- Configure `provcont` once so every client mode works concurrently.
- Do not use per-client server configurations.
- Do not reset, rewrite, or toggle server apt-cacher-ng/nginx settings between client tests.
- Do not introduce an apt-cache nginx mode variable that changes HTTP listener behavior for this lab.
- Use templates for apt-cacher-ng config, nginx site config, apt sources, apt proxy files, and aptly config.
- Use handlers for service restarts/reloads.
- Use `ansible.builtin.*` module names.
- Prefer Ansible idioms over shell scripts and ad hoc command tasks.
- Avoid `ansible.builtin.shell` entirely unless shell features are genuinely required.
- Avoid `ansible.builtin.command` when an Ansible module can express the same change.
- Use `ansible.builtin.apt` for package installation and apt cache updates.
- Use `ansible.builtin.template` for generated configuration files.
- Use `ansible.builtin.copy` for static files and small literal managed files.
- Use `ansible.builtin.file` for directories, ownership, modes, and symlinks.
- Use `ansible.builtin.lineinfile`, `blockinfile`, or templates for controlled text changes.
- Use `ansible.builtin.service` or `ansible.builtin.systemd_service` for services.
- Use `ansible.builtin.uri` for HTTP/HTTPS smoke tests where practical.
- Use handlers instead of inline restarts after config changes.
- Use `notify` only from tasks that can actually change managed state.
- Use `changed_when` and `failed_when` for read-only validation commands if a command is unavoidable.
- Use facts and variables instead of parsing command output.
- Do not use `trusted=yes` for Debian repositories.
- Do not disable TLS verification to make tests pass.
- Do not configure HTTPS CONNECT tunneling as the primary cache path.
- Make client modes mutually exclusive and idempotent.
- Preserve package authenticity through Debian archive signatures.

## Ansible Idiom Expectations

The implementation should look like normal Ansible roles, not translated shell scripts.

Package installation example:

```yaml
- name: Install apt-cacher-ng packages
  ansible.builtin.apt:
    name:
      - apt-cacher-ng
      - ca-certificates
      - curl
    state: present
    update_cache: true
```

Configuration example:

```yaml
- name: Configure apt-cacher-ng base settings
  ansible.builtin.template:
    src: apt-cacher-ng-base.conf.j2
    dest: /etc/apt-cacher-ng/00-provcont-base.conf
    owner: root
    group: root
    mode: "0644"
  notify: Restart apt-cacher-ng
```

Symlink example:

```yaml
- name: Enable nginx apt cache site
  ansible.builtin.file:
    src: /etc/nginx/sites-available/apt-cache.conf
    dest: /etc/nginx/sites-enabled/apt-cache.conf
    state: link
    owner: root
    group: root
  notify: Reload nginx
```

Smoke test example:

```yaml
- name: Check Debian InRelease through local apt-cacher-ng
  ansible.builtin.uri:
    url: "http://127.0.0.1:{{ apt_cacher_ng_port }}/debian/dists/{{ debian_release }}/InRelease"
    method: HEAD
    status_code: [200, 304]
```

Acceptable uses of `command` are limited to validation tools that have no first-class module, such as `nginx -t`. These tasks must be read-only and should not report changes:

```yaml
- name: Validate nginx configuration
  ansible.builtin.command: nginx -t
  changed_when: false
```

Do not use heredocs, `tee`, `sed -i`, inline bash scripts, or chained shell commands for managed configuration. Convert the intent into templates, files, variables, handlers, and normal module tasks.

## Open Design Notes

- The final recommended mode is `https_internal_domain`.
- `http_https_path` is useful for simple first tests and to verify apt-cacher-ng `HTTPS///` behavior.
- `http_proxy` verifies formal APT proxy mode and host-style remaps.
- `http_internal_domain` exists to test clean internal paths without client TLS. The lab nginx default must forward HTTP to apt-cacher-ng so this test can run at the same time as HTTPS clients.
- `ForceManaged` should stay disabled for the initial shared-server test matrix. It can be considered later only after every required client mode is proven against the same server configuration.
- Aptly should be installed and initialized independently from apt-cacher-ng.
- Aptly nginx exposure is part of the first implementation, using `aptly.provcont.lan` by default. Repository content creation can remain minimal at first; the nginx site should still be ready to serve `aptly_public_dir`.
