# Using apt-cacher-ng Securely

This document standardizes a secure `apt-cacher-ng` configuration for Debian clients.

The goal is:

```text
APT clients use controlled cache URLs or a controlled APT proxy
apt-cacher-ng still caches package objects
apt-cacher-ng fetches upstream repositories over HTTPS
APT package authenticity remains verified by Debian archive signatures
```

Do **not** use `trusted=yes` for normal Debian repositories. HTTPS protects the transport legs, but package authenticity still comes from the Debian archive signing keys already present on Debian systems.

## Terminology

This document uses three different access patterns:

```text
1. URL-through-cache mode
   Client sources point directly at apt-cacher-ng as if it were the repository server.

2. Formal APT proxy mode
   Client sources stay normal, and APT is configured with Acquire::http::Proxy.

3. HTTPS client-to-cache mode
   Clients speak HTTPS to a reverse proxy, which forwards plain HTTP to apt-cacher-ng on localhost.
```

The `HTTPS///` syntax is apt-cacher-ng's “tell-me-what-you-need” HTTPS URL method. It is specific to apt-cacher-ng. It is not a Debian mirror feature and not a standard APT URL convention.

---

## 1. HTTP Clients Using `HTTPS///`

`apt-cacher-ng` works well for HTTP APT clients, but we do not want the cache server itself to fetch packages over a plaintext Internet leg.

Switching clients directly to upstream HTTPS repositories is a natural reflex, but then `apt-cacher-ng` can only tunnel those HTTPS connections with `PassThroughPattern`, which does not provide useful package-object caching. That defeats the main purpose of using `apt-cacher-ng`.

Use a formal APT proxy configuration like this:

```conf
Acquire::http::Proxy "http://192.168.200.2:3142";
Acquire::https::Proxy "DIRECT";
```

Then use the following `HTTPS///` form in `/etc/apt/sources.list`. In this mode, APT sends a normal HTTP request to the configured proxy, and `apt-cacher-ng` interprets the `HTTPS///` URL prefix as an instruction to fetch the upstream repository over HTTPS.

Older examples sometimes show direct cache-host URLs such as `http://192.168.200.2:3142/HTTPS///...`. On current Debian Bookworm apt-cacher-ng builds, that shape can fail with `403 Configuration error (confusing proxy mode) or prohibited port`. The proxy form below is the shape this lab validates.

This lab sets `AllowUserPorts: 0` for apt-cacher-ng so the `HTTPS///` compatibility mode is not rejected by apt-cacher-ng's user-port guard. The remap-based modes remain the preferred secure shape because they avoid exposing `HTTPS///` source URLs to clients.

```sources.list
# Binary packages
deb http://HTTPS///deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://HTTPS///deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://HTTPS///security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://HTTPS///deb.debian.org/debian bookworm-backports main contrib non-free-firmware

# Source packages, optional
deb-src http://HTTPS///deb.debian.org/debian bookworm main contrib non-free-firmware
deb-src http://HTTPS///deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb-src http://HTTPS///security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src http://HTTPS///deb.debian.org/debian bookworm-backports main contrib non-free-firmware
```

The resulting flow is:

```text
APT client
  -> proxy http://192.168.200.2:3142
  -> request http://HTTPS///deb.debian.org/debian
  -> apt-cacher-ng
  -> https://deb.debian.org/debian
```

---

## 2. HTTP Clients Using Formal APT Proxy Mode and ACNG Remaps

Another way to make `apt-cacher-ng` fetch from upstream repositories over HTTPS is to use normal HTTP sources on the client, a formal APT proxy configuration, and server-side `Remap-*` rules.

The flow is:

```text
APT client has normal HTTP Debian sources
  ↓
APT sends HTTP repository requests to explicit APT proxy
  ↓
apt-cacher-ng receives request for http://deb.debian.org/debian/...
  ↓
Remap rule matches the request
  ↓
apt-cacher-ng fetches from https://deb.debian.org/debian/...
```

### Client `/etc/apt/sources.list`

```sources.list
# Binary packages
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware

# Source packages, optional
deb-src http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
```

### Client APT proxy configuration

Create `/etc/apt/apt.conf.d/00apt-cacher-ng-proxy`:

```conf
Acquire::http::Proxy "http://192.168.200.2:3142";
Acquire::https::Proxy "DIRECT";
```

The `Acquire::https::Proxy "DIRECT";` line is defensive. This pattern expects clients to use HTTP source URLs. If a client uses an `https://` source URL and sends it through ACNG with CONNECT tunneling, that traffic will not be usefully cached.

### Server HTTPS backend files

On the `apt-cacher-ng` server:

```bash
sudo tee /etc/apt-cacher-ng/backends_debian_https >/dev/null <<'EOF'
https://deb.debian.org/debian/
EOF

sudo tee /etc/apt-cacher-ng/backends_debian_security_https >/dev/null <<'EOF'
https://security.debian.org/debian-security/
EOF
```

### Server remap configuration

Create `/etc/apt-cacher-ng/99-provcont-remap.conf`:

```bash
sudo tee /etc/apt-cacher-ng/99-provcont-remap.conf >/dev/null <<'EOF'
# Client asks for http://deb.debian.org/debian/...
# ACNG fetches from https://deb.debian.org/debian/...
Remap-debian-https: deb.debian.org/debian ; file:backends_debian_https

# Client asks for http://security.debian.org/debian-security/...
# ACNG fetches from https://security.debian.org/debian-security/...
Remap-debian-security-https: security.debian.org/debian-security ; file:backends_debian_security_https
EOF
```

Restart the server and watch the logs:

```bash
sudo systemctl restart apt-cacher-ng
sudo systemctl status apt-cacher-ng --no-pager
sudo tail -f /var/log/apt-cacher-ng/apt-cacher.log /var/log/apt-cacher-ng/apt-cacher.err
```

Pull packages again from a client while watching the server logs:

```bash
sudo rm -rf /var/lib/apt/lists/*
sudo apt update
```

To specifically test formal proxy mode from a shell:

```bash
curl -I -x http://192.168.200.2:3142 \
  http://deb.debian.org/debian/dists/bookworm/InRelease
```

---

## 3. HTTPS Clients via Reverse Proxy

`apt-cacher-ng` cannot usefully cache packages when clients tunnel end-to-end HTTPS repository URLs through it with CONNECT/`PassThroughPattern`. To have HTTPS between clients and the cache while preserving caching, terminate TLS with a reverse proxy and forward plain HTTP to `apt-cacher-ng` on localhost.

The flow is:

```text
APT client
  -> HTTPS to apt-cache.provcont.lan
  -> nginx terminates TLS
  -> HTTP to 127.0.0.1:3142
  -> apt-cacher-ng
  -> HTTPS to upstream Debian repositories
```

This can be done in two ways:

```text
Option 1: HTTPS client-to-cache plus HTTPS/// source URLs
Option 2: HTTPS client-to-cache plus clean source URLs and ACNG remaps
```

Both options require a reverse proxy such as nginx, Caddy, or Apache if clients are going to use HTTPS to the cache host.

---

## 4. HTTPS Client Option 1: Reverse Proxy plus `HTTPS///`

This option uses the `HTTPS///` method without requiring a formal APT proxy configuration.

### Client `/etc/apt/sources.list`

```sources.list
# Binary packages
deb https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm main contrib non-free-firmware
deb https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb https://apt-cache.provcont.lan/HTTPS///security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm-backports main contrib non-free-firmware

# Source packages, optional
deb-src https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/HTTPS///security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/HTTPS///deb.debian.org/debian bookworm-backports main contrib non-free-firmware
```

The `apt-cache.provcont.lan` host must terminate TLS and forward the full path to `apt-cacher-ng` over HTTP.

### nginx reverse proxy

```nginx
server {
    listen 80;
    server_name apt-cache.provcont.lan;

    return 301 https://$host$request_uri;
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

---

## 5. HTTPS Client Option 2: Reverse Proxy plus Clean URLs and ACNG Remaps

This option hides `HTTPS///` from clients. Clients use clean internal HTTPS repository URLs, and `apt-cacher-ng` remaps those paths to HTTPS upstream repositories.

This is the best final shape when you want clients not to choose upstream transport details.

### Client `/etc/apt/sources.list`

```sources.list
# Binary packages
deb https://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian bookworm-updates main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian bookworm-backports main contrib non-free-firmware

# Source packages, optional
deb-src https://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/debian bookworm-updates main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
deb-src https://apt-cache.provcont.lan/debian bookworm-backports main contrib non-free-firmware
```

### Complete server and client setup script

```bash
#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Option 2: HTTPS client -> reverse proxy -> apt-cacher-ng -> HTTPS upstream
#
# Server:
#   apt-cache.provcont.lan / 192.168.200.2
#
# Client-visible repository URLs:
#   https://apt-cache.provcont.lan/debian
#   https://apt-cache.provcont.lan/debian-security
#
# Upstream URLs used by apt-cacher-ng:
#   https://deb.debian.org/debian/
#   https://security.debian.org/debian-security/
###############################################################################

###############################################################################
# 1. Server packages
###############################################################################

sudo apt update
sudo apt install -y apt-cacher-ng nginx ca-certificates curl
sudo update-ca-certificates

###############################################################################
# 2. Server TLS material
#
# Replace these files with your real internal-CA-signed certificate and key.
# The certificate must be valid for:
#
#   apt-cache.provcont.lan
#
# Expected files:
#
#   /etc/ssl/provcont/apt-cache.crt
#   /etc/ssl/provcont/apt-cache.key
###############################################################################

sudo install -d -m 0755 /etc/ssl/provcont

# Example only:
# sudo cp apt-cache.crt /etc/ssl/provcont/apt-cache.crt
# sudo cp apt-cache.key /etc/ssl/provcont/apt-cache.key

sudo chmod 0644 /etc/ssl/provcont/apt-cache.crt
sudo chmod 0600 /etc/ssl/provcont/apt-cache.key
sudo chown root:root /etc/ssl/provcont/apt-cache.crt /etc/ssl/provcont/apt-cache.key

###############################################################################
# 3. apt-cacher-ng base config
#
# Bind ACNG to localhost only. nginx will expose HTTPS publicly.
###############################################################################

sudo tee /etc/apt-cacher-ng/00-provcont-base.conf >/dev/null <<'EOF_BASE'
Port: 3142
BindAddress: 127.0.0.1

# Enable only after all remaps are verified.
# This makes ACNG accept only requests matched by Remap-* rules.
# ForceManaged: 1
EOF_BASE

###############################################################################
# 4. apt-cacher-ng HTTPS backend files
#
# These are the real upstream HTTPS repositories.
###############################################################################

sudo tee /etc/apt-cacher-ng/backends_debian_https >/dev/null <<'EOF_DEBIAN_BACKEND'
https://deb.debian.org/debian/
EOF_DEBIAN_BACKEND

sudo tee /etc/apt-cacher-ng/backends_debian_security_https >/dev/null <<'EOF_SECURITY_BACKEND'
https://security.debian.org/debian-security/
EOF_SECURITY_BACKEND

###############################################################################
# 5. apt-cacher-ng remap rules
#
# Client/nginx/ACNG local paths:
#
#   /debian/...
#   /debian-security/...
#
# are remapped to HTTPS upstreams.
###############################################################################

sudo tee /etc/apt-cacher-ng/10-provcont-remaps.conf >/dev/null <<'EOF_REMAPS'
# Local client-visible path:
#   /debian/...
#
# Upstream:
#   https://deb.debian.org/debian/...
Remap-debian-https: /debian ; file:backends_debian_https

# Local client-visible path:
#   /debian-security/...
#
# Upstream:
#   https://security.debian.org/debian-security/...
Remap-debian-security-https: /debian-security ; file:backends_debian_security_https
EOF_REMAPS

###############################################################################
# 6. Restart and inspect apt-cacher-ng
###############################################################################

sudo systemctl restart apt-cacher-ng
sudo systemctl enable apt-cacher-ng
sudo systemctl status apt-cacher-ng --no-pager

sudo journalctl -u apt-cacher-ng -n 80 --no-pager || true
sudo tail -n 80 /var/log/apt-cacher-ng/apt-cacher.err || true

###############################################################################
# 7. nginx HTTPS reverse proxy
#
# Public:
#   https://apt-cache.provcont.lan/*
#
# Backend:
#   http://127.0.0.1:3142/*
###############################################################################

sudo tee /etc/nginx/sites-available/apt-cache.provcont.lan >/dev/null <<'EOF_NGINX'
server {
    listen 80;
    server_name apt-cache.provcont.lan;

    return 301 https://$host$request_uri;
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
EOF_NGINX

sudo ln -sf /etc/nginx/sites-available/apt-cache.provcont.lan \
  /etc/nginx/sites-enabled/apt-cache.provcont.lan

sudo nginx -t
sudo systemctl reload nginx
sudo systemctl enable nginx

###############################################################################
# 8. Server-side smoke tests
###############################################################################

curl -I http://127.0.0.1:3142/debian/dists/bookworm/InRelease
curl -I http://127.0.0.1:3142/debian-security/dists/bookworm-security/InRelease

curl -I https://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I https://apt-cache.provcont.lan/debian-security/dists/bookworm-security/InRelease

###############################################################################
# 9. Optional strict mode
#
# Enable only after the smoke tests above work.
###############################################################################

# sudo sed -i 's/^# ForceManaged: 1/ForceManaged: 1/' \
#   /etc/apt-cacher-ng/00-provcont-base.conf
#
# sudo systemctl restart apt-cacher-ng

###############################################################################
# 10. Client setup
#
# Run the following section on each Debian Bookworm client.
###############################################################################

cat <<'CLIENT_COMMANDS'

###############################################################################
# CLIENT COMMANDS START HERE
###############################################################################

# 1. Make sure the cache hostname resolves.
#
# Prefer DNS. For quick testing only, use /etc/hosts:
#
#   192.168.200.2 apt-cache.provcont.lan

# echo '192.168.200.2 apt-cache.provcont.lan' | sudo tee -a /etc/hosts

# 2. Install the internal CA certificate that signed apt-cache.provcont.lan.
#
# Copy your CA certificate to the client first, then:
#
#   sudo install -m 0644 provcont-ca.crt /usr/local/share/ca-certificates/provcont-ca.crt
#   sudo update-ca-certificates

# 3. Optional: ensure APT does not use a separate explicit proxy.
#
# Option 2 uses repository URL mode, not Acquire::http::Proxy mode.

sudo tee /etc/apt/apt.conf.d/00-no-apt-proxy >/dev/null <<'EOF_NO_PROXY'
Acquire::http::Proxy "false";
Acquire::https::Proxy "false";
EOF_NO_PROXY

# 4. Back up and replace sources.list with clean HTTPS cache URLs.

sudo cp -a /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S) || true

sudo tee /etc/apt/sources.list >/dev/null <<'EOF_CLIENT_SOURCES'
deb https://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian bookworm-updates main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
deb https://apt-cache.provcont.lan/debian bookworm-backports main contrib non-free-firmware

# Source repositories are optional. Enable only if you need apt source/build-dep workflows.
# deb-src https://apt-cache.provcont.lan/debian bookworm main contrib non-free-firmware
# deb-src https://apt-cache.provcont.lan/debian bookworm-updates main contrib non-free-firmware
# deb-src https://apt-cache.provcont.lan/debian-security bookworm-security main contrib non-free-firmware
# deb-src https://apt-cache.provcont.lan/debian bookworm-backports main contrib non-free-firmware
EOF_CLIENT_SOURCES

# 5. Test TLS and apt.

curl -I https://apt-cache.provcont.lan/debian/dists/bookworm/InRelease
curl -I https://apt-cache.provcont.lan/debian-security/dists/bookworm-security/InRelease

sudo rm -rf /var/lib/apt/lists/*
sudo apt update

###############################################################################
# CLIENT COMMANDS END HERE
###############################################################################

CLIENT_COMMANDS

###############################################################################
# 11. Server log checks after client apt update
###############################################################################

echo
echo "After running apt update from a client, check:"
echo
echo "  sudo tail -f /var/log/apt-cacher-ng/apt-cacher.log"
echo "  sudo tail -f /var/log/apt-cacher-ng/apt-cacher.err"
echo "  sudo find /var/cache/apt-cacher-ng -maxdepth 5 -type f | head -100"
echo
```

---

## Optional: Strict Managed Mode

After all required repositories work, you can enable strict managed mode:

```bash
sudo sed -i 's/^# ForceManaged: 1/ForceManaged: 1/' \
  /etc/apt-cacher-ng/00-provcont-base.conf
sudo systemctl restart apt-cacher-ng
```

This makes `apt-cacher-ng` accept only requests matched by configured `Remap-*` rules. Use this only after testing all required Debian repositories, security repositories, and any third-party repositories you plan to support.

---

## Final Recommended Shape

For simple first tests, use `HTTPS///` source URLs directly.

For the final managed setup, use HTTPS client-to-cache with clean paths and remaps:

```text
Client sources:
  https://apt-cache.provcont.lan/debian
  https://apt-cache.provcont.lan/debian-security

nginx:
  https://apt-cache.provcont.lan/*
  -> http://127.0.0.1:3142/*

apt-cacher-ng:
  /debian
  -> https://deb.debian.org/debian/

  /debian-security
  -> https://security.debian.org/debian-security/
```
