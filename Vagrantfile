require "rbconfig"

VAGRANT_BOX = "debian/bookworm64"
LAB_NETWORK = "mkosi-lab"
LAB_HOST_IP = "192.168.200.1"

MACHINES = {
  "provcont" => "192.168.200.2",
  "client-http-https-path" => "192.168.200.3",
  "client-http-proxy" => "192.168.200.4",
  "client-http-internal-domain" => "192.168.200.5",
  "client-https-internal-domain" => "192.168.200.6"
}.freeze

SSH_FORWARD_PORTS = {
  "provcont" => 2222,
  "client-http-https-path" => 2200,
  "client-http-proxy" => 2201,
  "client-http-internal-domain" => 2202,
  "client-https-internal-domain" => 2203
}.freeze

def requested_provider
  provider_arg = ARGV.find { |arg| arg.start_with?("--provider=") }
  return provider_arg.split("=", 2).last if provider_arg

  provider_flag_index = ARGV.index("--provider")
  return ARGV[provider_flag_index + 1] if provider_flag_index

  ENV["VAGRANT_DEFAULT_PROVIDER"]
end

provider = requested_provider || "libvirt"
run_validate = ENV.fetch("SECURE_ACNG_RUN_VALIDATE", "0")

def windows_host?
  RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/i)
end

Vagrant.configure("2") do |config|
  if provider == "libvirt"
    config.trigger.before :up do |trigger|
      trigger.info = "Ensuring libvirt network #{LAB_NETWORK} exists"
      trigger.run = { inline: "scripts/ensure-libvirt-network.sh" }
    end
  end

  if windows_host? && ENV["SECURE_ACNG_SKIP_WSL_ANSIBLE"] != "1"
    config.trigger.after :up do |trigger|
      trigger.info = "Running Ansible from WSL"
      trigger.only_on = "client-https-internal-domain"
      trigger.run = {
        inline: "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/run-wsl-ansible.ps1 -RepoPath \"#{Dir.pwd}\" -RunValidate \"#{run_validate}\""
      }
    end

    config.trigger.after :reload do |trigger|
      trigger.info = "Running Ansible from WSL"
      trigger.only_on = "client-https-internal-domain"
      trigger.run = {
        inline: "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/run-wsl-ansible.ps1 -RepoPath \"#{Dir.pwd}\" -RunValidate \"#{run_validate}\""
      }
    end
  end

  MACHINES.each do |name, ip|
    config.vm.define name do |m|
      m.vm.box = VAGRANT_BOX
      m.vm.hostname = name
      m.vm.synced_folder ".", "/vagrant", disabled: true
      m.ssh.insert_key = false

      if provider == "libvirt"
        m.vm.network "private_network",
          ip: ip,
          libvirt__network_name: LAB_NETWORK,
          libvirt__host_ip: LAB_HOST_IP,
          libvirt__dhcp_start: "192.168.200.10",
          libvirt__dhcp_stop: "192.168.200.254"
      else
        m.vm.network "private_network", ip: ip
      end

      m.vm.provider "virtualbox" do |vb|
        vb.name = "secure-acng-#{name}"
        vb.memory = 512
      end

      if windows_host?
        m.vm.network "forwarded_port",
          guest: 22,
          host: SSH_FORWARD_PORTS.fetch(name),
          host_ip: "0.0.0.0",
          id: "ssh",
          auto_correct: true
      end
    end
  end
end
