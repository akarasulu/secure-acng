# aptly_server

Installs aptly and configures a separate nginx site for `aptly.provcont.lan`.

This role does not alter the apt-cacher-ng nginx site.

The role creates aptly mirror definitions with normal HTTP Debian URLs and runs mirror management with `http_proxy` pointed at apt-cacher-ng. Apt-cacher-ng remaps those HTTP upstream requests to HTTPS, so aptly mirror updates use the cache without weakening the Internet transport leg.

Use `/usr/local/bin/aptly-acng mirror update <name>` for manual mirror updates through the cache.
