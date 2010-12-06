if node[:instance_role] =~ /^app/
  remote_file "/etc/nginx/servers/keep.upload.location.conf" do
    source "upload.location.conf"
    owner "deploy"
    group "deploy"
    mode 0755
  end

  directory '/mnt/temp_uploads/' do
    owner 'deploy'
    group 'deploy'
    mode  '0755'
    action :create
    recursive true
  end
end
