install_dir = node[:kafka][:install_dir]
distrib = "kafka-#{node[:kafka][:version]}-incubating-src"
user = node[:kafka][:user]
java_home   = node['java']['java_home']

# set up service-control
template "#{install_dir}/#{distrib}/bin/broker-control" do
  source  "service-control.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :server_config => "#{install_dir}/config/server.properties",
    :install_dir => "#{install_dir}/#{distrib}",
    :log_dir => node[:kafka][:log_dir],
    :java_home => java_home,
    :java_jmx_port => node[:kafka][:jmx_port],
    :java_class => "kafka.Kafka",
    :user => user
  })
end

# create the runit service
runit_service "kafka" do
  options({
    :log_dir => node[:kafka][:log_dir],
    :install_dir => "#{install_dir}/#{distrib}",
    :java_home => java_home,
    :user => user
  })
end

# start up Kafka broker
service "kafka" do
  action :start
end

# announce service
announce(:kafka, :broker)
