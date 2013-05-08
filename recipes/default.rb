#
# Cookbook Name::	kafka
# Description:: Base configuration for Kafka
# Recipe:: default
#
# Copyright 2013, OCTO Technology
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

# == Recipes
include_recipe "java"
include_recipe "runit"

java_home   = node['java']['java_home']

java_ark "jdk" do
  bin_cmds ["java", "javac"]
  action :install
end

user = node[:kafka][:user]
group = node[:kafka][:group]

if node[:kafka][:broker_id].nil? || node[:kafka][:broker_id].empty?
		node.set[:kafka][:broker_id] = node[:ipaddress].gsub(".","")
end

if node[:kafka][:broker_host_name].nil? || node[:kafka][:broker_host_name].empty?
		node.set[:kafka][:broker_host_name] = node[:fqdn]
end

log "Broker id: #{node[:kafka][:broker_id]}"
log "Broker name: #{node[:kafka][:broker_host_name]}"

group group do
end

user user do
  comment "Kafka user"
  gid "kafka"
  home "/home/kafka"
  shell "/bin/noshell"
  supports :manage_home => false
end

install_dir = node[:kafka][:install_dir]

directory "#{install_dir}" do
  owner "root"
  group "root"
  mode 00755
  recursive true
  action :create
end

directory node[:kafka][:log_dir] do
  owner   user
  group   group
  mode    00755
  recursive true
  action :create
end

directory node[:kafka][:data_dir] do
  owner   user
  group   group
  mode    00755
  recursive true
  action :create
end

distrib = "kafka-#{node[:kafka][:version]}-incubating-src"
tarball = "#{distrib}.tgz"
download_file = "#{node[:kafka][:download_url]}/#{tarball}"

remote_file "#{Chef::Config[:file_cache_path]}/#{tarball}" do
  source download_file
  mode 00644
  checksum node[:kafka][:checksum]
end

execute "tar" do
  user  "root"
  group "root"
  cwd install_dir
  command "tar zxvf #{Chef::Config[:file_cache_path]}/#{tarball}"
end

# grab the zookeeper nodes that are currently available
zookeeper_pairs = Array.new
if not Chef::Config.solo
  search(:node, "role:zookeeper_server AND chef_environment:#{node.chef_environment}").each do |n|
    zookeeper_pairs << n[:fqdn]
  end
end

# if no ZK found, add localhost
zookeeper_pairs = ["localhost"] if zookeeper_pairs.empty?
zookeeper_port = node[:zookeeper][:client_port] || 2181

# append the zookeeper client port (defaults to 2181)
i = 0
while i < zookeeper_pairs.size do
  zookeeper_pairs[i] = zookeeper_pairs[i].concat(":#{zookeeper_port}")
  i += 1
end

%w[server.properties log4j.properties].each do |template_file|
  template "#{install_dir}/#{distrib}/config/#{template_file}" do
    source	"#{template_file}.erb"
    owner user
    group group
    mode  00755
    variables({
      :kafka => node[:kafka],
      :zookeeper_pairs => zookeeper_pairs,
      :client_port => node[:zookeeper][:client_port]
    })
  end
end

# set up service-control
template "#{install_dir}/#{distrib}/bin/service-control" do
  source  "service-control.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :install_dir => "#{install_dir}/#{distrib}",
    :log_dir => node[:kafka][:log_dir],
    :java_home => java_home,
    :java_jmx_port => node[:kafka][:jmx_port],
    :java_class => "kafka.Kafka",
    :user => user
  })
end

execute "chmod" do
  command "find #{install_dir} -name bin -prune -o -type f -exec chmod 644 {} \\; && find #{install_dir} -type d -exec chmod 755 {} \\;"
  action :run
end

execute "chown" do
  command "chown -R root:root #{install_dir}"
  action :run
end

execute "chmod" do
  command "chmod -R 755 #{install_dir}/#{distrib}/bin"
  action :run
end

execute "sbt update" do
  user  "root"
  group "root"
  command "bash sbt update"
  cwd "#{install_dir}/#{distrib}"
  action :run
end

execute "sbt package" do
  user  "root"
  group "root"
  command "bash sbt package"
  cwd "#{install_dir}/#{distrib}"
  action :run 
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
