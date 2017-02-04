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

require 'json'
require 'timeout'
require 'fileutils'
require 'open-uri'
require 'logger'

RELEASES_JSON_URL = ENV['RELEASES_JSON_URL'] || 'https://download.go.cd/experimental/releases.json'

task :test_migration do
    begin
      download_addons
      sh "GO_VERSION=#{full_version} vagrant up centos-7 --provider #{ENV['PROVIDER'] || 'virtualbox'} --provision"
    rescue => e
      raise "Migration testing failed. Error message #{e.message}"
    ensure
      sh "vagrant destroy centos-7 --force"
    end
end

def download_addons
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  myhash = json.sort {|a, b| a['go_full_version'] <=> b['go_full_version']}.reverse
  myhash.each_with_index do |key, index|
    if full_version.include? myhash[index]['go_full_version']
      if (!File.exists?("addons/go-postgresql-#{key['go_full_version']}.jar"))
        sh "curl -k -o addons/#{addon_for(key['go_full_version'])} #{ENV['ADDON_DOWNLOAD_URL']}/#{key['go_full_version']}/#{addon_for(key['go_full_version'])}"
      end
    end
  end
end

def full_version
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  json.sort {|a, b| a['go_full_version'] <=> b['go_full_version']}.last['go_full_version']
end

def addon_for(core)
  versions_map = JSON.parse(File.read('./addons/addon_builds.json'))
  versions_map.select{|v| v['gocd_version'] == core}.last['addons']['postgresql']
end
