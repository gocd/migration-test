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

require 'open-uri'
require 'timeout'
require 'json'
require 'tmpdir'
require 'net/http'

PIPELINE_NAME = 'testpipeline'

class Redhat
  include Rake::DSL if defined?(Rake::DSL)

  def repo
    open('/etc/yum.repos.d/gocd.repo', 'w') do |f|
      f.puts('[gocd]')
      f.puts('name=gocd')
      f.puts('baseurl=https://download.gocd.io')
      f.puts('enabled=1')
      f.puts('gpgcheck=1')
      f.puts('gpgkey=https://download.gocd.io/GOCD-GPG-KEY.asc')
      f.puts('[gocd-exp]')
      f.puts('name=gocd-exp')
      f.puts('baseurl=https://download.gocd.io/experimental')
      f.puts('enabled=1')
      f.puts('gpgcheck=1')
      f.puts('gpgkey=https://download.gocd.io/GOCD-GPG-KEY.asc')
    end
    sh("yum makecache --disablerepo='*' --enablerepo='gocd*'")
  end

  def install(pkg_name, pkg_verion)
    sh("yum install --assumeyes #{pkg_name}-#{pkg_verion}")
  end

  def uninstall(pkg_name,pkg_verion)
    sh("yum remove --assumeyes #{pkg_name}-#{pkg_verion}")
  end

  def setup_postgres()
    sh("yum install --assumeyes postgresql-server")
    sh("yum install --assumeyes postgresql-contrib")
    sh(%Q{sudo -H -u postgres bash -c 'initdb -D /var/lib/pgsql/data'})
    sh("service postgresql start")
    sh(%Q{sudo -H -u postgres bash -c 'sed -i 's/peer/md5/g' /var/lib/pgsql/data/pg_hba.conf'})
    sh(%Q{sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"})
    sh("service postgresql restart")
    sh(%Q{sudo -H -u postgres bash -c 'createdb -U postgres cruise'})
  end

end

{
  'centos'     => Redhat,
}.each do |os, klass|
  namespace os do
    @postgres_setup_done='No'

    def trigger_pipeline
      url = "http://localhost:8153/go/api/pipelines/#{PIPELINE_NAME}/schedule"
      puts 'trigger the pipeline'
      sh(%Q{curl -sL -w "%{http_code}" -X POST -H "Accept:application/vnd.go.cd.v1+text" -H "CONFIRM:true" #{url} -o /dev/null})
    end

    def postgres_peoperties_in(path)
      sh(%Q{sudo -H -u go bash -c 'echo "db.host=localhost"  >> #{path}/postgresqldb.properties'})
      sh(%Q{sudo -H -u go bash -c 'echo "db.port=5432"  >> #{path}/postgresqldb.properties'})
      sh(%Q{sudo -H -u go bash -c 'echo "db.name=cruise"  >> #{path}/postgresqldb.properties'})
      sh(%Q{sudo -H -u go bash -c 'echo "db.user=postgres"  >> #{path}/postgresqldb.properties'})
      sh(%Q{sudo -H -u go bash -c 'echo "db.password=postgres"  >> #{path}/postgresqldb.properties'})
    end

    def service_status(migrated)
      puts 'wait for server to come up'
      sh('wget http://localhost:8153/go/about --waitretry=120 --retry-connrefused --quiet -O /dev/null')

      # check if server startup with postgres only
      if migrated == 'Yes'
        Timeout.timeout(120) do
          loop do
            if File.open('/var/log/go-server/go-server.log').lines.any?{|line| line.include?('Using connection configuration jdbc:postgresql://localhost:5432/cruise [User: postgres] [Password Encrypted: false]')}
              p 'server up with postgres'
              break
            end
          end
        end
      end


      puts 'wait for agent to come up'
      Timeout.timeout(180) do
        loop do
          agents = JSON.parse(open('http://localhost:8153/go/api/agents', 'Accept' => "application/vnd.go.cd.v4+json").read)['_embedded']['agents']

          if agents.any? { |a| a['agent_state'] == 'Idle' }
            puts 'Agent is up'
            break
          end
        end
      end
    end

    def check_pipeline_in_cctray label
      begin
        timeout(180) do
          while(true) do
            response = open("http://localhost:8153/go/cctray.xml").read
              if response.include? %Q(<Project name="#{PIPELINE_NAME} :: defaultStage" activity="Sleeping" lastBuildStatus="Success" lastBuildLabel="#{label}") then
                puts "Pipeline completed successfully"
                break
              end
          end
        end
      end
      rescue Timeout::Error
        raise "Pipeline was not built successfully. Wait timed out"
    end

    task :repo do
      klass.new.repo
    end

    task :install do
       klass.new.install('go-server', ENV['GO_VERSION'])
       klass.new.install('go-agent', ENV['GO_VERSION'])
       sh('service go-server start')
       sh('service go-agent start')
    end

    task :start do
       sh('service go-server start')
       sh('service go-agent start')
    end

    task :setup_postgres do
      p 'Setting up postgres'
      klass.new.setup_postgres
    end

    task :setup_addon do
      sh('echo ''GO_SERVER_SYSTEM_PROPERTIES=\"\$GO_SERVER_SYSTEM_PROPERTIES -Dgo.database.provider=com.thoughtworks.go.postgresql.PostgresqlDatabase\"''>> /etc/default/go-server')

      version_revision = ENV['GO_VERSION']
      version = version_revision.split('-')[0]
      sh(%Q{sudo -H -u go bash -c 'mkdir -p /var/lib/go-server/addons ; cp /vagrant/addons/go-postgresql-#{version}-* /var/lib/go-server/addons/'})
      postgres_peoperties_in("/etc/go")
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
      sh(%Q{curl -sL -w "%{http_code}" -X POST  -H "Accept: application/vnd.go.cd.v2+json" -H "Content-Type: application/json" --data "@/vagrant/rakelib/pipeline.json" #{url} -o /dev/null})
    end


    task :unpause_pipeline do
      url = "http://localhost:8153/go/api/pipelines/#{PIPELINE_NAME}/unpause"
      puts 'unpause the pipeline'
      sh(%Q{curl -sL -w "%{http_code}" -X POST  -H "Accept:application/vnd.go.cd.v1+text" -H "CONFIRM:true" #{url} -o /dev/null})
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
      sh('service go-server stop')
      sh('service go-agent stop')
    end

    task :migrate do
      migration_location = "#{Dir.tmpdir()}/migration"
      url = "http://localhost:8153/go/api/backups"
      uri = URI(url)
      request = Net::HTTP::Post.new(uri.path)
      request.add_field("Accept", "application/vnd.go.cd.v1+json")
      request.add_field("Confirm", "true")
      response = Net::HTTP.start(uri.host,uri.port) do |http|
        http.request(request)
      end
      raise "Go Server backup failed with error: #{response.body}" unless response.is_a?(Net::HTTPOK)
      backup_path = JSON.parse(response.body)['path']
      sh('service go-server stop')

      sh(%Q{sudo -H -u go bash -c 'mkdir -p #{migration_location}/config ; cp /vagrant/addons/go-postgresql-*.jar #{migration_location}'})
      sh(%Q{sudo -H -u go bash -c 'unzip #{backup_path}/db.zip -d #{migration_location}'})
      postgres_peoperties_in("#{migration_location}/config")
      cd migration_location do
        sh(%Q{sudo -H -u go bash -c 'java -Dcruise.config.dir=#{migration_location}/config -Dgo.h2.db.location=#{migration_location} -jar go-postgresql-#{ENV['GO_VERSION']}.jar'})
      end
    end

    task :migration_test => [:repo, :install, :check_service_is_up, :create_pipeline, :unpause_pipeline, :pipeline_status, :setup_postgres, :migrate, :setup_addon, :start, :check_service_is_up_w_postgres, :trigger_pipeline, :pipeline_status_after_migration]

  end
end
