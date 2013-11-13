install_dir = node[:kafka][:install_dir]
distrib = "kafka-#{node[:kafka][:version]}-src"
user = node[:kafka][:user]
java_home   = node['java']['java_home']

## rewrite consumer properties if this is set
if node[:kafka][:consumer_zk_discover_in]
  zookeeper_pairs = Array.new
  if not Chef::Config.solo
    zookeeper_pairs = discover_all(:zookeeper, :server,
                                   node[:kafka][:consumer_zk_discover_in]).map(&:private_hostname).sort
  end

  # if no ZK found, add localhost
  zookeeper_pairs = ["localhost"] if zookeeper_pairs.empty?
  zookeeper_port = (node[:zookeeper] && node[:zookeeper][:client_port]) || 2181

  # append the zookeeper client port (defaults to 2181)
  i = 0
  while i < zookeeper_pairs.size do
    zookeeper_pairs[i] = zookeeper_pairs[i].concat(":#{zookeeper_port}")
    i += 1
  end

  # rewrite consumer properties file. only ZK should have changed.
  %w[consumer.properties].each do |template_file|
    template "#{install_dir}/#{distrib}/config/#{template_file}" do
      source	"#{template_file}.erb"
      owner user
      group group
      mode  00755
      variables({
                  :kafka => node[:kafka],
                  :zookeeper_pairs => zookeeper_pairs,
                  :client_port => zookeeper_port
                })
    end
  end
end


# set up service-control
template "#{install_dir}/#{distrib}/bin/migration-control" do
  source  "service-control.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :server_config => "",
    :install_dir => "#{install_dir}/#{distrib}",
    :log_dir => node[:kafka][:log_dir],
    :kafka_opts => "--kafka.07.jar kafka-0.7.19.jar --zkclient.01.jar zkclient-0.2.0.jar --num.producers #{node[:kafka][:migration_tool_producers]} --consumer.config=config/consumer.properties --producer.config=config/producer.properties --whitelist=#{node[:kafka][:mirrormaker_whitelist]}",
    :java_home => java_home,
    :java_class => "kafka.tools.KafkaMigrationTool",
    :user => user
  })
end

# create the runit service
runit_service "migration_tool" do
  options({
    :log_dir => node[:kafka][:log_dir],
    :install_dir => "#{install_dir}/#{distrib}",
    :java_home => java_home,
    :user => user
  })
end

# start up migration tool
service "migration_tool" do
  action :start
end