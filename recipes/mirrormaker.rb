install_dir = node[:kafka][:install_dir]
distrib = "kafka-#{node[:kafka][:version]}-incubating-src"
user = node[:kafka][:user]
java_home   = node['java']['java_home']


# set up service-control
template "#{install_dir}/#{distrib}/bin/mirrormaker-control" do
  source  "service-control.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :install_dir => "#{install_dir}/#{distrib}",
    :log_dir => node[:kafka][:log_dir],
    :kafka_opts => "--consumer.config config/consumer.properties --producer.config config/producer.properties --whitelist=#{node[:kafka][:mirrormaker_whitelist]}",
    :java_home => java_home,
    :java_jmx_port => node[:kafka][:jmx_port],
    :java_class => "kafka.tools.MirrorMaker",
    :user => user
  })
end

# create the runit service
runit_service "mirrormaker" do
  options({
    :log_dir => node[:kafka][:log_dir],
    :install_dir => "#{install_dir}/#{distrib}",
    :java_home => java_home,
    :user => user
  })
end

# start up mirrormaker
service "mirrormaker" do
  action :start
end
