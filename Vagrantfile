VAGRANT_BOX = "debian/bookworm64"
LAB_NETWORK = "provcont-lab"
LAB_HOST_IP = "192.168.202.1"

MACHINES = {
  "provcont" => "192.168.202.2",
  "client-http-https-path" => "192.168.202.11",
  "client-http-proxy" => "192.168.202.12",
  "client-http-internal-domain" => "192.168.202.13",
  "client-https-internal-domain" => "192.168.202.14"
}.freeze

Vagrant.configure("2") do |config|
  config.trigger.before :up do |trigger|
    trigger.info = "Ensuring libvirt network #{LAB_NETWORK} exists"
    trigger.run = { inline: "scripts/ensure-libvirt-network.sh" }
  end

  MACHINES.each do |name, ip|
    config.vm.define name do |m|
      m.vm.box = VAGRANT_BOX
      m.vm.hostname = name
      m.vm.synced_folder ".", "/vagrant", disabled: true
      m.ssh.insert_key = false

      m.vm.network "private_network",
        ip: ip,
        libvirt__network_name: LAB_NETWORK,
        libvirt__host_ip: LAB_HOST_IP,
        libvirt__dhcp_start: "192.168.202.10",
        libvirt__dhcp_stop: "192.168.202.254"
    end
  end
end
