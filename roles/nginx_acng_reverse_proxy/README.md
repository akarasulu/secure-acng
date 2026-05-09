# nginx_acng_reverse_proxy

Creates one nginx site for `apt-cache.provcont.lan`.

Both HTTP and HTTPS listeners proxy to apt-cacher-ng. The lab intentionally does not redirect HTTP to HTTPS because one client mode must prove clean HTTP internal-domain operation against the same server.
