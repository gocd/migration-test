##########################################################################
# Copyright 2018 ThoughtWorks, Inc.
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

require 'json'
require 'timeout'
require 'fileutils'
require 'open-uri'
require 'logger'

RELEASES_JSON_URL = ENV['RELEASES_JSON_URL'] || 'https://download.go.cd/experimental/releases.json'

task :test_migration do
  begin
    download_addons
    boot_centos_container
    run_command = %(bash -lc "rake --trace --rakefile /migration/rakelib/migrate.rake centos:migration_test GO_VERSION=#{full_version}")
    sh "docker exec centos #{run_command}"
  rescue StandardError => e
    raise "Migration testing failed. Error message #{e.message}"
  ensure
    sh "docker stop centos"
  end
end

def download_addons
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  myhash = json.sort_by { |a| a['go_full_version'] }.reverse
  myhash.each_with_index do |key, index|
    next unless full_version.include? myhash[index]['go_full_version']
    unless File.exist?("addons/go-postgresql-#{key['go_full_version']}.jar")
      sh "curl --fail -L -k -o addons/#{addon_for(key['go_full_version'])} --user '#{ENV['EXTENSIONS_USER']}:#{ENV['EXTENSIONS_PASSWORD']}'  #{ENV['ADDON_DOWNLOAD_URL']}/#{key['go_full_version']}/download?eula_accepted=true"
    end
  end
end

def full_version
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  json.select { |x| x['go_version'] == ENV['GO_VERSION'] }.sort_by { |a| a['go_build_number'] }.last['go_full_version']
end

def addon_for(core)
  versions_map = JSON.parse(File.read('./addons/addon_builds.json'))
  versions_map.select { |v| v['gocd_version'] == core }.last['addons']['postgresql']
end

def boot_centos_container
  pwd = File.dirname(__FILE__)

  sh 'docker stop centos' do |_ok, _res|
    puts 'box centos does not exist, ignoring!'
  end

  sh 'docker rm centos' do |_ok, _res|
    puts 'box centos does not exist, ignoring!'
  end

  sh 'docker pull centos:7'

  sh %(docker run --volume #{pwd}:/migration -d -it --name centos centos:7 /bin/bash)

  sh 'docker exec centos yum install -y epel-release centos-release-scl sysvinit-tools'
  sh 'docker exec centos yum install -y unzip git wget rh-ruby22-rubygem-rake'
  sh "docker exec centos /bin/bash -lc 'echo source /opt/rh/rh-ruby22/enable > /etc/profile.d/ruby-22.sh'"
end
