if node[:instance_role] =~ /^app/
  remote_file "/engineyard/bin/copier" do
    source "copier"
    owner "root"
    group "root"
    mode 0755
  end

  node[:applications].each do |app_name,data|
    1.times do |count| # TODO: Use multiple copiers later
      template "/etc/monit.d/copier#{count+1}.#{app_name}.monitrc" do
        source "copier.monitrc.erb"
        owner "root"
        group "root"
        mode 0644
        variables({
          :app_name => app_name,
          :user => node[:owner_name],
          :worker_name => "copier#{count+1}",
          :framework_env => node[:environment][:framework_env]
        })
      end
    end

    execute "monit-reload-restart" do
       command "sleep 30 && monit reload"
       action :run
    end
  end
end
