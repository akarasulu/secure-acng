# apt_cache_client

Configures one Debian client for one cache mode. The mode changes only client-side files; it never changes the shared `provcont` apt-cacher-ng or nginx configuration.

Supported `apt_cache_client_mode` values:

- `http_https_path`
- `http_proxy`
- `http_internal_domain`
- `https_internal_domain`
