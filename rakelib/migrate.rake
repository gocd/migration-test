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

require 'open-uri'
require 'timeout'
require 'json'
require 'tmpdir'
require 'net/http'

PIPELINE_NAME = 'testpipeline'.freeze

class Redhat
  include Rake::DSL if defined?(Rake::DSL)

  def repo
    open('/etc/yum.repos.d/gocd.repo', 'w') do |f|
      f.puts('[gocd]')
      f.puts('name=gocd')
      f.puts('baseurl=https://download.gocd.org')
      f.puts('enabled=1')
      f.puts('gpgcheck=1')
      f.puts('gpgkey=https://download.gocd.org/GOCD-GPG-KEY.asc')
      f.puts('[gocd-exp]')
      f.puts('name=gocd-exp')
      f.puts('baseurl=https://download.gocd.org/experimental')
      f.puts('enabled=1')
      f.puts('gpgcheck=1')
      f.puts('gpgkey=https://download.gocd.org/GOCD-GPG-KEY.asc')
    end
    sh("yum makecache --disablerepo='*' --enablerepo='gocd*'")
  end

  def install(pkg_name, pkg_verion)
    sh("yum install --assumeyes #{pkg_name}-#{pkg_verion}")
  end

  def uninstall(pkg_name, pkg_verion)
    sh("yum remove --assumeyes #{pkg_name}-#{pkg_verion}")
  end

  def setup_postgres
    sh('yum install --assumeyes postgresql-server')
    sh('yum install --assumeyes postgresql-contrib')
    sh(%(su - postgres -c bash -c 'initdb -D /var/lib/pgsql/data'))
    sh(%(su - postgres -c bash -c 'pg_ctl -D /var/lib/pgsql/data -l /var/lib/pgsql/data/logfile start' && sleep 10))
    sh(%(su - postgres -c bash -c 'sed -i 's/peer/md5/g' /var/lib/pgsql/data/pg_hba.conf'))
    sh(%(su - postgres -c /bin/bash -c "psql -c \\"ALTER USER postgres WITH PASSWORD 'postgres'\\";"))
    sh(%(su - postgres -c bash -c 'createdb -U postgres cruise'))
    sh(%(su - postgres -c bash -c 'pg_ctl -D /var/lib/pgsql/data -l /var/lib/pgsql/data/logfile restart'))
  end
end

{
  'centos' => Redhat
}.each do |os, klass|
  namespace os do
    @postgres_setup_done = 'No'
    @addon_version = nil

    def trigger_pipeline
      url = "http://localhost:8153/go/api/pipelines/#{PIPELINE_NAME}/schedule"
      puts 'trigger the pipeline'
      sh(%(curl -sL -w "%{http_code}" -X POST -H "Accept:application/vnd.go.cd.v1+json" -H "X-GoCD-Confirm:true" #{url} -o /dev/null))
    end

    def postgres_peoperties_in(path)
      sh(%(su - go bash -c 'echo "db.host=localhost"  >> #{path}/postgresqldb.properties'))
      sh(%(su - go bash -c 'echo "db.port=5432"  >> #{path}/postgresqldb.properties'))
      sh(%(su - go bash -c 'echo "db.name=cruise"  >> #{path}/postgresqldb.properties'))
      sh(%(su - go bash -c 'echo "db.user=postgres"  >> #{path}/postgresqldb.properties'))
      sh(%(su - go bash -c 'echo "db.password=postgres"  >> #{path}/postgresqldb.properties'))
    end



    def service_status(migrated)
      puts 'wait for server to come up'
      #sh('wget http://localhost:8153/go/about --waitretry=600 --retry-connrefused --quiet -O /dev/null')
      sleep 300
      # check if server startup with postgres only
      if migrated == 'Yes'
        Timeout.timeout(120) do
          loop do
            if File.open('/var/log/go-server/go-server.log').lines.any? { |line| line.include?('Using connection configuration jdbc:postgresql://localhost:5432/cruise [User: postgres] [Password Encrypted: false]') }
              p 'server up with postgres'
              break
            end
          end
        end
      end

      puts 'wait for agent to come up'
      Timeout.timeout(180) do
        loop do
          agents = JSON.parse(open('http://localhost:8153/go/api/agents', 'Accept' => 'application/vnd.go.cd.v4+json').read)['_embedded']['agents']

          if agents.any? { |a| a['agent_state'] == 'Idle' }
            puts 'Agent is up'
            break
          end
        end
      end
    end

    def check_pipeline_in_cctray(label)
      begin
        timeout(180) do
          loop do
            response = open('http://localhost:8153/go/cctray.xml').read
            if response.include? %(<Project name="#{PIPELINE_NAME} :: defaultStage" activity="Sleeping" lastBuildStatus="Success" lastBuildLabel="#{label}")
              puts 'Pipeline completed successfully'
              break
            end
          end
        end
      end
    rescue Timeout::Error
      raise 'Pipeline was not built successfully. Wait timed out'
    end

    task :repo do
      klass.new.repo
    end

    task :install do
      klass.new.install('go-server', ENV['GO_VERSION'])
      klass.new.install('go-agent', ENV['GO_VERSION'])
      chmod_R 0755, '/migration/rakelib/with-java.sh'
      sh("./migration/rakelib/with-java.sh /etc/init.d/go-server start")
      sh('/etc/init.d/go-agent start')
    end

    task :start do
      sh("./migration/rakelib/with-java.sh /etc/init.d/go-server start")
      sh('/etc/init.d/go-agent start')
    end

    task :setup_postgres do
      p 'Setting up postgres'
      klass.new.setup_postgres
    end

    task :setup_addon do
      sh('echo ''GO_SERVER_SYSTEM_PROPERTIES=\"\$GO_SERVER_SYSTEM_PROPERTIES -Dgo.database.provider=com.thoughtworks.go.postgresql.PostgresqlDatabase\"''>> /etc/default/go-server')

      sh(%(su - go bash -c 'mkdir -p /var/lib/go-server/addons ; cp /migration/addons/#{@addon_version} /var/lib/go-server/addons/'))
      postgres_peoperties_in('/etc/go')
    end

    task :check_service_is_up do
      service_status('No')
    end

    task :check_service_is_up_w_postgres do
      service_status('Yes')
    end

    task :create_pipeline do
      url = 'http://localhost:8153/go/api/admin/pipelines'
      puts 'create a pipeline'
      sh(%(curl -sL -w "%{http_code}" -X POST  -H "Accept: application/vnd.go.cd.v6+json" -H "Content-Type: application/json" --data "@/migration/rakelib/pipeline.json" #{url} -o /dev/null))
    end


    task :trigger_pipeline do
      trigger_pipeline
    end

    task :pipeline_status do
      check_pipeline_in_cctray 1
    end

    task :pipeline_status_after_migration do
      check_pipeline_in_cctray 2
    end

    task :stop do
      sh('/etc/init.d/go-server stop')
      sh('/etc/init.d/go-agent stop')
    end

    task :migrate do
      migration_location = "#{Dir.tmpdir}/migration"
      uri = URI.parse('http://localhost:8153/go/api/backups')

      header = { 'Accept' => 'application/vnd.go.cd.v1+json', 'Confirm' => 'true' }
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.request_uri, header)

      # Send the request
      response = http.request(request)
      raise "Go Server backup failed with error: #{response.body}" unless response.is_a?(Net::HTTPOK)
      backup_path = JSON.parse(response.body)['path']
      @addon_version = postgres_jar_for server_version
      sh('/etc/init.d/go-server stop')

      sh(%(su - go bash -c 'mkdir -p #{migration_location}/config ; cp /migration/addons/#{@addon_version} #{migration_location}'))
      sh(%(su - go bash -c 'unzip #{backup_path}/db.zip -d #{migration_location}'))
      postgres_peoperties_in("#{migration_location}/config")


      cd migration_location do
        sh(%(su - go bash -c 'java -Dcruise.config.dir=#{migration_location}/config -Dgo.h2.db.location=#{migration_location} -jar /migration/addons/#{@addon_version}'))
      end
    end

    def postgres_jar_for(core)
      versions_map = JSON.parse(File.read('/migration/addons/addon_builds.json'))
      versions_map.select { |v| v['gocd_version'] == core }.last['addons']['postgresql']
    end

    def server_version
      versions = JSON.parse(open('http://localhost:8153/go/api/version', 'Accept' => 'application/vnd.go.cd.v1+json').read)
      "#{versions['version']}-#{versions['build_number']}"
    end

    task migration_test: %i[repo install check_service_is_up create_pipeline pipeline_status setup_postgres migrate setup_addon start check_service_is_up_w_postgres trigger_pipeline pipeline_status_after_migration]
  end
end
