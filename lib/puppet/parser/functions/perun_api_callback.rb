require 'net/http'
require 'net/https'
require 'openssl'
require 'json'


module Puppet::Parser::Functions
  newfunction(:perun_api_callback, :type => :rvalue, :doc=> <<-EOS
This function makes RPC call to perun RPC API. 
The function expects four arguments, and has the following format:

  perun_api_call(host, user, password, method)

host: string containing API (server) host, e.g., 'perun.cesnet.cz'
user: string containing user name, e.g., 'cerit-sc-admin-api'
password: strint containinig user password
method: string containing RPC call method, e.g., 'createFacility'

On success, function returns hash response. On fail, function rises an exception.
EOS
  ) do |arguments|

  unless lookupvar('module_name') == 'perunapi' then
      raise(Puppet::ParseError, "perun_api_call(): " +
            "Internal function of module 'perun_api_call'")
  end

  hostname, user, password, method = arguments

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

  uri = URI("https://#{hostname}/krbes/rpc/jsonp/getPendingRequests?callbackId=#{caller_host}-#{method}")

  Net::HTTP.start(uri.host, uri.port,
    :use_ssl => uri.scheme == 'https') do |http|
    
     req = Net::HTTP::Get.new(uri.request_uri, initheader = {'Cookie' => cookie})

     if user.empty?
         # temporary hack to use my own credentials
         user, password = File.read('/etc/puppetlabs/perun.pass').chomp.split(' ')
     end

     req.basic_auth user, password

     begin
       response = http.request req

       if response.code != '200' and response.code != '400'
           raise(Puppet::ParseError, "perun_api_post(): #{response.code} - #{response.body}")
       end
     rescue Timeout::Error => e
       return JSON.parse('{"timeout": true}')
     end

     ret = response.body.sub(/^[^\(]*\((.*)\);/, '\1')
 
     f = File.new('/tmp/callback', 'w', 0600)
     f.write(ret)
     f.close
 
     if ret == 'null'
        return {}
     else
        return JSON.parse(ret)
     end
  end
 end
end
