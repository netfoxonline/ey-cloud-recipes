
if node[:instance_role] == 'db_master'
  execute "install pg9" do
    command "emerge =dev-db/postgresql-server-9.0.2"
    environment({ "ACCEPT_KEYWORDS" => "~x86" })
    action :run
  end
end
