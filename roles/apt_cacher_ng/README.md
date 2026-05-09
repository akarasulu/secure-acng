# apt_cacher_ng

Installs and configures one apt-cacher-ng instance that supports all lab client modes at the same time.

The lab default binds apt-cacher-ng to `0.0.0.0:3142` so direct cache clients and formal APT proxy clients can reach it. Nginx separately handles the internal-domain HTTP and HTTPS modes.
