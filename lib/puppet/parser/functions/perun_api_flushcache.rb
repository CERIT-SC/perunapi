module Puppet::Parser::Functions
  newfunction(:perun_api_flushcache, :doc=> <<-EOS
This function makes RPC call to perun RPC API. 
The function expects six arguments, and has the following format:

  perun_api_flushcache(manager, method, cachename)

manager: string containing RPC call manager, e.g., 'facilitiesManager'
method: string containing RPC call method, e.g., 'createFacility'
cachetag: string containing cache tag

On success, function returns hash response. On fail, function rises an exception.
EOS
  ) do |arguments|

  unless lookupvar('module_name') == 'perunapi' then
      raise(Puppet::ParseError, "perun_api_call(): " +
            "Internal function of module 'perun_api_call'")
  end

  manager, method, cachetag = arguments

  if cachetag != nil 
     cachetag = "-#{cachetag}"
  else
     cachetag = ''
  end

  path = '/var/lib/puppet/perun_cache/'
  unless Puppet::FileSystem.exist?(path)
    Dir.mkdir(path, 0700)
  end
 
  caller_host = lookupvar('clusterfullname')

  cache_name = "#{path}/#{caller_host}-#{manager}-#{method}#{cachetag}"

  if cache_name =~ /\.\./
     raise(Puppet::ParseError, "perun_api_flushcache(): malicious use of cache filename!")
  end

  if Puppet::FileSystem.exist?("#{cache_name}-req")
    File.unlink("#{cache_name}-req")
  end

  if Puppet::FileSystem.exist?("#{cache_name}-resp")
    File.unlink("#{cache_name}-resp")
  end

 end
end
