define perunapi::host (
           $ensure = 'present',
  String $hostname = $facts['fqdn'],
  String $cluster  = $::clusterfullname,
  Hash $attributes = {},
) {

  if $ensure == 'present' {

    $_query_hosts = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                   'facilitiesManager', 'getHostsByHostname', { 'hostname' => $facts['fqdn']}, $facts['fqdn'])

    if $_query_hosts != undef {
       $_host_ids = $_query_hosts.map |$_host| {
          $_host['id']
       }
    }

    if $attributes.keys.size > 0 {
       $attributes.keys.each |$_attr| {
          if $_attr =~ /:host:/ {
             
             $_host_ids.each |$_host_id| {
                $_attribute = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                             'attributesManager', 'getAttribute', {'host' => $_host_id, 'attributeName' => $_attr}, "${_host_id}${_attr}")

                if $attributes[$_attr] == 'null' {
                   $_newattr = undef
                } elsif $attributes[$_attr] =~ String and $attributes[$_attr] =~ /^[0-9]*$/ {
                   $_newattr = scanf("${attributes[$_attr]}", "%i")[0]
                } else {
                   $_newattr = $attributes[$_attr]
                }
                if $_attribute['id'] != undef and $_attribute['value'] != $_newattr {
                   $_newval = {'value' => $_newattr}
                   $_res = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                               'attributesManager', 'setAttribute', {'host' => $_host_id, 
                                                                     'attribute' => merge($_attribute, $_newval)}, 'nocache')

                   perun_api_flushcache('attributesManager', 'getAttribute', "${_host_id}${_attr}")

                   if $_res != undef and $_res['errorId'] != undef and $_res['message'] != undef {
                      fail("Cannot set attribute: $_attr. Reason: ${_res['message']}")
                   } else {
                      notify{"setAttribute_${_attr}${_host_id}":
                        message => "Setting attribute ${_attr} to value ${_newattr}.",
                     }
                  }
                }
                if $_attribute['id'] == undef {
                   notify{"Warning: undefined attribute name $_attr for host $_host_id":}
                   perun_api_flushcache('attributesManager', 'getAttribute', "${_host_id}${_attr}")
                }
            }
          }
       }
    }   
  }
}
