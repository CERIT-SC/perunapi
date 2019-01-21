class perunapi (
  Integer $version            = 1,
  String  $perun_api_host     = $perunapi::params::perun_api_host,
  String  $perun_api_user     = $perunapi::params::perun_api_user,
  String  $perun_api_password = $perunapi::params::perun_api_password,
) inherits ::perunapi::params {
 
  $_perunapi = lookup('perunapi')

  if $_perunapi['facility'] != undef {
     $_query = perun_api_call($perun_api_host, $perun_api_user, $perun_api_password,
                              'vosManager', 'getVoByShortName', {'shortName' => $_perunapi['facility']['vo'] }, 
                              $_perunapi['facility']['vo'])
     if $_query == undef {
        fail("Cannot get VO ${_perunapi['facility']['vo']} ID")
     }

        perunapi::facility{$_perunapi['facility']['name']:
           ensure       => present,
           description  => $_perunapi['facility']['description'],
           manager      => $_perunapi['facility']['manager'],
           owner        => $_perunapi['facility']['owner'],
           vo           => $_query['id'],
           customhosts  => $_perunapi['facility']['customhosts'],
           attributes   => $_perunapi['attributes'],
           services     => $_perunapi['services'],
       }

       if $_perunapi['resources'] != undef {
          $_perunapi['resources'].each |$_resource| {
              perunapi::resource{"${_resource['name']}${_resource['vo']}":
                 resource   => $_resource,
                 facility   => $_perunapi['facility']['name'],
                 attributes => $_perunapi['attributes'],
                 services   => $_perunapi['services'],
              }
          }
       }

     perunapi::host{$_perunapi['facility']['name']:
        attributes => $_perunapi['attributes'],
     }

     perunapi::pbsmon{$_perunapi['facility']['name']:
        attributes => $_perunapi['pbsmon'],
     }
  }
}
