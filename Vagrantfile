# -*- mode: ruby -*-
# vi: set ft=ruby :

ENV['VAGRANT_NO_PARALLEL'] = 'yes'
Vagrant.configure(2) do |config|
  #
  #Install vagrant-scp and vagrant-vbguest plugins
 config.vagrant.plugins = ["vagrant-scp", "vagrant-vbguest"]
  # Common provisioning code for all VMs
 # config.vm.provision "shell", path: "bootstrap.sh"
 config.vm.provision "shell", path: "step_1_bootstrap.sh"
  
 DNS_Name = "lk8s.net"

   # Initial Kubernetes Master Servers
 MasterCount = 3
 # 3 Kubernetes Masters
 (1..MasterCount).each do |m|
  config.vm.define "kmaster#{m}" do |kmaster|
    kmaster.vm.box = "kub-base-centos76"
    kmaster.vm.synced_folder ".", "/vagrant", type: "virtualbox"
    kmaster.vm.hostname = "kmaster#{m}.#{DNS_Name}"
    kmaster.vm.network "public_network", ip: "192.168.0.2#{m}"
    kmaster.vm.network "private_network", ip: "10.10.10.2#{m}",
    virtualbox__intnet: true
    kmaster.vm.provider "virtualbox" do |v|
      v.name = "kmaster#{m}"
      v.memory = 2048
      v.cpus = 2
      v.customize ["modifyvm", :id, "--nictype1", "virtio"]
      v.customize ["modifyvm", :id, "--nictype2", "virtio"]
      v.customize ["modifyvm", :id, "--nictype3", "virtio"]
    end
  end
 end

  NodeCount = 3
 # Add 3 Kubernetes Worker Nodes
  (1..NodeCount).each do |i|
    config.vm.define "node#{i}" do |workernode|
      workernode.vm.box = "kub-base-centos76"
      workernode.vm.synced_folder ".", "/vagrant", type: "virtualbox"
      workernode.vm.hostname = "node#{i}.#{DNS_Name}"
      workernode.vm.network "public_network", ip: "192.168.0.4#{i}"
      workernode.vm.network "private_network", ip: "10.10.10.4#{i}",
      virtualbox__intnet: true
      workernode.vm.provider "virtualbox" do |v|
        v.name = "node#{i}"
        v.memory = 4096
        v.cpus = 4
        v.customize ["modifyvm", :id, "--nictype1", "virtio"]
        v.customize ["modifyvm", :id, "--nictype2", "virtio"]
        v.customize ["modifyvm", :id, "--nictype3", "virtio"]
      end
    end
  end

 # Nginx LB Node
  config.vm.define "lb" do |lb|
    lb.vm.box = "kub-base-centos76"
    lb.vm.synced_folder ".", "/vagrant", type: "virtualbox"
    lb.vm.hostname = "lb.#{DNS_Name}"
    lb.vm.network "public_network", ip: "192.168.0.10"
    lb.vm.network "private_network", ip: "10.10.10.10",
    virtualbox__intnet: true
    lb.vm.provider "virtualbox" do |v|
      v.name = "lb.lk8s.net"
      v.memory = 1048
      v.cpus = 1
      v.customize ["modifyvm", :id, "--nictype1", "virtio"]
      v.customize ["modifyvm", :id, "--nictype2", "virtio"]
      v.customize ["modifyvm", :id, "--nictype3", "virtio"]
    end
  end
end
