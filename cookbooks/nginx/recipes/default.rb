
if node[:instance_role] =~ /^app/
  enable_package "www-servers/nginx" do
    version "0.7*"
  end

  package "www-servers/nginx" do
    version "0.7.65-r2"
    action :install
  end

  service "nginx" do
    supports :status => true, :stop => true, :restart => true, :staus => true
    action :restart
  end

  remote_file "/etc/nginx/common/proxy.conf" do
    source "common.proxy.conf"
    owner "deploy"
    group "deploy"
    mode 0755
  end
end
