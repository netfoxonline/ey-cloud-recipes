if node[:instance_role] =~ /^app/
  template "/home/deploy/.pgpass" do
    owner 'deploy'
    group 'deploy'
    mode 0600
    source "pgpass.erb"
    variables({
      :hostname => node[:db_host],
      :dbuser => node[:users].first[:username],
      :dbpass => node[:users].first[:password]
    })
  end

end
