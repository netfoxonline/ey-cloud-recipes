
if node[:instance_role] =~ /^app/
  enable_package "www-servers/nginx" do
    version "0.7*"
  end

  package "www-servers/nginx" do
    action :remove
  end

  package 'make'

  remote_file "nginx" do
    path "/tmp/nginx-0.8.53.tar.gz"
    source 'http://nginx.org/download/nginx-0.8.53.tar.gz'
  end

  remote_file "nginx-upload" do
    path "/tmp/nginx_upload_module-2.2.0.tar.gz"
    source 'http://www.grid.net.ru/nginx/download/nginx_upload_module-2.2.0.tar.gz'
  end

  directory "/tmp/nginx-build" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end

  script "make-install-nginx" do
    interpreter "bash"
    user "root"
    cwd "/tmp/nginx-build"
    # should this rm -rf /root/nginx dir first?
    code <<-EOC
      /etc/init.d/nginx stop
      tar zxvf /tmp/nginx-0.8.53.tar.gz
      tar zxvf /tmp/nginx_upload_module-2.2.0.tar.gz
      cd ./nginx-0.8.53
      ./configure --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --sbin-path=/usr/sbin --with-http_ssl_module --add-module=../nginx_upload_module-2.2.0
      make 
      make install
      /etc/init.d/nginx start
    EOC
  end

  remote_file "/etc/nginx/common/proxy.conf" do
    source "common.proxy.conf"
    owner "deploy"
    group "deploy"
    mode 0755
  end

  service "nginx" do
    supports :status => true, :stop => true, :restart => true
    action :restart
  end
end
