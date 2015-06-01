install_dir = node[:kafka][:install_dir]
distrib = "kafka-#{node[:kafka][:version]}-src"
user = node[:kafka][:user]
java_home   = node['java']['java_home']

# explicit announce of mirrormake service, so that brokers do not add mm in their producer.properties
# if mm and broker service are running on the same host, also announce it early on, so that this recipe
# does not add itself to the broker_list
announce(:kafka, :mirrormaker)

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
  zookeeper_chroot = node[:kafka][:mirrormaker][:zk_chroot]

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
                  :zookeeper_chroot => zookeeper_chroot,
                  :client_port => zookeeper_port
                })
    end
  end
end

if node[:kafka][:producer_zk_discover_in]
  zookeeper_pairs = Array.new
  if not Chef::Config.solo
    zookeeper_pairs = discover_all(:zookeeper, :server,
                                   node[:kafka][:producer_zk_discover_in]).map(&:private_hostname).sort
  end

  # if no ZK found, add localhost
  zookeeper_pairs = ["localhost"] if zookeeper_pairs.empty?
  zookeeper_port = (node[:zookeeper] && node[:zookeeper][:client_port]) || 2181
  zookeeper_chroot = node[:kafka][:mirrormaker][:producer_zk_chroot] || node[:kafka][:mirrormaker][:zk_chroot]

  # append the zookeeper client port (defaults to 2181)
  i = 0
  while i < zookeeper_pairs.size do
    zookeeper_pairs[i] = zookeeper_pairs[i].concat(":#{zookeeper_port}")
    i += 1
  end

  broker_pairs = Array.new
if not Chef::Config.solo
  broker_pairs = discover_all(:kafka, :broker).map(&:private_hostname).sort
end


  broker_pairs = [node[:kafka][:broker_host_name]] if broker_pairs.empty?

  log "Found brokers: #{broker_pairs}"

  i = 0
  while i < broker_pairs.size do
    broker_pairs[i] = broker_pairs[i].dup.concat(":#{node[:kafka][:port]}")
    i += 1
  end

  # rewrite producer properties file. only ZK should have changed.
  %w[producer.properties].each do |template_file|
    template "#{install_dir}/#{distrib}/config/#{template_file}" do
      source	"#{template_file}.erb"
      owner user
      group group
      mode  00755
      variables({
                  :kafka => node[:kafka],
                  :broker_pairs => broker_pairs,
                  :zookeeper_pairs => zookeeper_pairs,
                  :zookeeper_chroot => zookeeper_chroot,
                  :client_port => zookeeper_port
                })
    end
  end
end


# set up service-control
template "#{install_dir}/#{distrib}/bin/mirrormaker-control" do
  source  "service-control.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :server_config => "",
    :install_dir => "#{install_dir}/#{distrib}",
    :log_dir => node[:kafka][:log_dir],
    :kafka_opts => "--consumer.config config/consumer.properties --producer.config config/producer.properties --whitelist=#{node[:kafka][:mirrormaker_whitelist]}",
    :java_home => java_home,
    :java_jmx_port => node[:kafka][:mirrormaker][:jmx_port],
    :java_class => "kafka.tools.MirrorMaker",
    :user => user,
    :heap_opts => node[:kafka][:heap_opts]
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
