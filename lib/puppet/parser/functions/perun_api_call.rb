require 'net/http'
require 'net/https'
require 'openssl'
require 'json'


module Puppet::Parser::Functions
  newfunction(:perun_api_call, :type => :rvalue, :doc=> <<-EOS
This function makes RPC call to perun RPC API. 
The function expects six arguments, and has the following format:

  perun_api_call(host, user, password, manager, method, request, cachename)

host: string containing API (server) host, e.g., 'perun.cesnet.cz'
user: string containing user name, e.g., 'cerit-sc-admin-api'
password: strint containinig user password
manager: string containing RPC call manager, e.g., 'facilitiesManager'
method: string containing RPC call method, e.g., 'createFacility'
request: hash containing RPC call data, e.g., { 'name' => 'testfacility, 'description' => 'test description' }
cachetag: string containing cache tag, if 'nocache' is set then no caching is done

On success, function returns hash response. On fail, function rises an exception.
EOS
  ) do |arguments|

  unless lookupvar('module_name') == 'perunapi' then
      raise(Puppet::ParseError, "perun_api_call(): " +
            "Internal function of module 'perun_api_call'")
  end

  hostname, user, password, manager, method, request, cachetag = arguments

  request = request.to_json.gsub(/"undef"/, "null")

  caller_host = lookupvar('clusterfullname')
  if caller_host == nil
     caller_host = lookupvar('fqdn')
  end

  path = '/var/lib/puppet/perun_cache/'
  unless Puppet::FileSystem.exist?(path)
    Dir.mkdir(path, 0700)
  end
 
  cookiefile = "#{path}/#{caller_host}-cookie"

  cookie = ''

  if Puppet::FileSystem.exist?(cookiefile)
    cookie = File.read(cookiefile)
  end

  if cachetag != 'nocache'
    if cachetag != nil 
       cachetag = "-#{cachetag}"
    else
       cachetag = ''
    end

    cache_name = "#{path}/#{caller_host}-#{manager}-#{method}#{cachetag}"

    if cache_name =~ /\.\./
       raise(Puppet::ParseError, "perun_api_call(): malicious use of cache filename!")
    end
  
    if Puppet::FileSystem.exist?("#{cache_name}-req")
      oldreq = File.read("#{cache_name}-req")
    else
      oldreq = ''
      f = File.new("#{cache_name}-req", 'w', 0600)
      f.write(request)
      f.close
    end

    if oldreq == request
      if Puppet::FileSystem.exist?("#{cache_name}-resp")
        mtime = File.mtime("#{cache_name}-resp")
        if (Time.new - mtime) < 3600*24*4
          return JSON.parse(File.read("#{cache_name}-resp"))
        end
      end
    else 
      f = File.new("#{cache_name}-req", 'w', 0600)
      f.write(request)
      f.close
    end
  end
  
  uri = URI("https://#{hostname}/krbes/rpc/json/#{manager}/#{method}?callback=#{caller_host}-#{method}")

  Net::HTTP.start(uri.host, uri.port, read_timeout: 60,
    :use_ssl => uri.scheme == 'https') do |http|
    
     req = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' =>'application/json', 'Cookie' => cookie})

     if user.empty?
         # temporary hack to use my own credentials
         user, password = File.read('/etc/puppetlabs/perun.pass').chomp.split(' ')
     end

     req.basic_auth user, password
     req.body = request

     begin
       response = http.request req

       rawcookies = response.get_fields('set-cookie')

       if rawcookies != nil     
          cookie = rawcookies[0].split('; ')[0]
       end

       f = File.new(cookiefile, 'w', 0600)
       f.write(cookie)
       f.close

       if response.code != '200' and response.code != '400'
           raise(Puppet::ParseError, "perun_api_post(): #{response.code} - #{response.body}")
       end

       if cachetag != 'nocache'
          f = File.new("#{cache_name}-resp", 'w', 0600)
          f.write(response.body)
          f.close
       end
     rescue Timeout::Error => e
       return JSON.parse('{"timeout": true}')
     end

     if response.body == 'null'
       return {}
     else
       return JSON.parse(response.body)
     end
  end
 end
end
