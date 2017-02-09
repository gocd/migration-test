##########################################################################
# Copyright 2017 ThoughtWorks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  boxes = {
    'centos-7'     => {virtualbox: 'boxcutter/centos73'},
  }

  boxes.each do |name, box_cfg|
    config.vm.define name do |vm_config|
      vm_config.vm.network "private_network", type: "dhcp"
      vm_config.vm.provision "shell", inline: "yum makecache"
      vm_config.vm.provision "shell", inline: "yum install -y epel-release centos-release-scl"
      vm_config.vm.provision "shell", inline: "yum install -y java-1.8.0-openjdk unzip git rh-ruby22-rubygem-rake"
      vm_config.vm.provision "shell", inline: "echo 'source /opt/rh/rh-ruby22/enable' > /etc/profile.d/ruby-22.sh"
      vm_config.vm.provision "shell", inline: "sudo -i GO_VERSION=#{ENV['GO_VERSION']} rake --trace --rakefile /vagrant/rakelib/migrate.rake centos:migration_test"


      vm_config.vm.provider :virtualbox do |vb, override|
        override.vm.box = box_cfg[:virtualbox]
        vb.gui    = ENV['GUI'] || false
        vb.memory = ((ENV['MEMORY'] || 4).to_f * 1024).to_i
        vb.cpus   = 4
        vb.customize ['modifyvm', :id, '--cableconnected1', 'on']
      end

      vm_config.vm.provider :vmware_fusion do |vm, override|
        override.vm.box = box_cfg[:virtualbox]
        vm.gui    = ENV['GUI'] || false
        vm.memory = ((ENV['MEMORY'] || 4).to_f * 1024).to_i
        vm.cpus   = 4
      end
    end
  end

   if Vagrant.has_plugin?('vagrant-cachier')
      config.cache.scope = :box
      config.cache.enable :yum
   end
end
