class ASYD < Sinatra::Application
  get '/hosts/overiew' do
    status 200
    @groups = Hostgroup.all
    @hosts = Host.all
    @host_status = {}
    @hosts.each do |host|
      @host_status[host.hostname] = host.is_ok?
    end
    erb :hosts_overiew
  end

  get '/host/:host' do
    status 200
    @host = Host.first(:hostname => params[:host])
    @host.get_status
    if @host.nil?
      erb :oops
    else
      erb :host_detail
    end
  end

  post '/host/add' do
    status 200
    Host.new(params['hostname'], params['ip'], params['user'], params['ssh_port'].to_i, params['password'])
    hostlist = '/hosts/overiew'
    redirect to hostlist
  end

  post '/host/del' do
    status 200
    if params['revoke'] == "true"
      revoke = true
    else
      revoke = false
    end
    host = Host.first(:hostname => params['hostname'])
    host.delete(revoke)
    hostlist = '/hosts/overiew'
    redirect to hostlist
  end

  post '/host/reboot' do
    host = Host.first(:hostname => params['hostname'])
    host.exec_cmd("reboot")
    hostlist = '/hosts/overiew'
    redirect to hostlist
  end

  post '/host/add-var' do
    status 200
    host = Host.first(:hostname => params['hostname'])
    host.add_var(params['var_name'], params['value'])
    redir = '/host/'+params['hostname']
    redirect to redir
  end

  post '/host/del-var' do
    status 200
    host = Host.first(:hostname => params['hostname'])
    host.del_var(params['var_name'])
    redir = '/host/'+params['hostname']
    redirect to redir
  end
end
