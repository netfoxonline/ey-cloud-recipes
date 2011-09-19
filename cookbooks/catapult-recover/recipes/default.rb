#
# Cookbook Name:: catapult-recover
# Recipe:: default
#
# This recipe just adds the recovery scripts to each instance.
# 

#TODO create /mnt/backups/restore
if node[:instance_role] == 'db_master'
  directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  
  directory "/mnt/restore" do
    owner "deploy"
    group "deploy"
    mode "0755"
    action :create
  end
  
  remote_file "/data/backups/catapult_database_restore.rb" do
    source "catapult_database_restore.rb"
    owner "root"
    group "root"
    mode "0755"
  end
end

if node[:instance_role] == 'app_master'
  directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  
  directory "/mnt/restore" do
    owner "deploy"
    group "deploy"
    mode "0755"
    action :create
  end
  
  remote_file "/data/backups/catapult_resources_restore.rb" do
    source "catapult_resources_restore.rb"
    owner "root"
    group "root"
    mode "0755"
  end
end

if node[:instance_role] == 'util'
  directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  
  directory "/mnt/restore" do
    owner "deploy"
    group "deploy"
    mode "0755"
    action :create
  end
  
  remote_file "/data/backups/catapult_answers_restore.rb" do
    source "catapult_answers_restore.rb"
    owner "root"
    group "root"
    mode "0755"
  end
  
  remote_file "/data/backups/catapult_documents_restore.rb" do
    source "catapult_documents_restore.rb"
    owner "root"
    group "root"
    mode "0755"
  end
end
