if node[:instance_role] == 'util'
 directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  remote_file "/data/backups/catapult_s3_documents_and_answers_backups.rb" do
    source "catapult_s3_documents_and_answers_backups.rb"
    owner "root"
    group "root"
    mode "0755"
  end
  cron "daily_s3_backups" do
    minute  '0'
    hour    '9'
    user    'root'
    command "# cd /mnt/ && sudo ruby /data/backups/catapult_s3_documents_and_answers_backups.rb | sudo tee output.log"
  end
end

if node[:instance_role] == 'db_master'
 directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  remote_file "/data/backups/catapult_database_backups.rb" do
    source "catapult_database_backups.rb"
    owner "root"
    group "root"
    mode "0755"
  end
  cron "daily_db_backups" do
    minute  '0'
    hour    '9'
    user    'root'
    command "ruby /data/backups/catapult_database_backups.rb"
  end
end

if node[:instance_role] == 'app_master'
 directory "/data/backups" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end
  remote_file "/data/backups/catapult_resources_and_source_code_backups.rb" do
    source "catapult_resources_and_source_code_backups.rb"
    owner "root"
    group "root"
    mode "0755"
  end
 cron "daily_app_backups" do
    minute  '0'
    hour    '9'
    user    'root'
    command "# ruby /data/backups/catapult_resources_and_source_code_backups.rb"
  end
end
