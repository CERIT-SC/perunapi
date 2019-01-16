define perunapi::facility (
         $ensure,
  String $description,
  Hash $manager        = { 'users' => [$::perunapi::user]},   
  Array $owner         = [$::perunapi::user],
  Integer $vo,
  Array $customhosts   = [],
  Hash  $attributes    = {},
  Hash  $services      = {},
) {

  if $ensure == 'present' {

    $_query = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                             'facilitiesManager', 'getFacilityByName', {'name' => $title}, $title)

    if $_query != undef and $_query['name'] == 'FacilityNotExistsException' {   
       $_createfacility_req = { 'facility' => {'id' => 0, 'name' => $title, 'description' => $description }}

       $_resp = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                               'facilitiesManager', 'createFacility', $_createfacility_req, 'nocache')

       if $_resp['id'] != undef {
           $_facility_id = $_resp['id']
       }
       notify{'create_facility':
           message => "Creating facility $title",
       }
       perun_api_flushcache('facilitiesManager', 'getFacilityByName', $title)
    } else {
       if $_query['id'] != undef {
           $_facility_id = $_query['id']
       } 
    }

    if $_facility_id == undef {
       fail("Did not find or create facility: $title")
    }

    $_query_admin_users = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                        'facilitiesManager', 'getAdmins', {'facility' => $_facility_id, 'onlyDirectAdmins' => 'true' })

    $_adm_users = $_query_admin_users.map |$user| {
       $user['lastName']
    }

    $_add_adm_users = $manager['users'] - $_adm_users

    $_query_admin_groups = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                        'facilitiesManager', 'getAdminGroups', {'facility' => $_facility_id})

    $_adm_groups = $_query_admin_groups.map |$_group| {
       $_group['name']
    }

    $_add_adm_groups = $manager['groups'] - $_adm_groups

    if $_add_adm_users.size > 0 {
        $_add_adm_users.each |$_user| {
           $_query_user = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                         'membersManager', 'findMembersInVo', {'searchString' => $user, 'vo' => $vo}, $_user)
           $_user_id = $_query_user[0]['userId']
           perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                          'facilitiesManager', 'addAdmin', {'facility' => $_facility_id , 'user' => $_user_id}, 'nocache')
           perun_api_flushcache('facilitiesManager', 'getAdmins')
        }
        notify{'addAdmins':
           message => "Adding admins: $_add_ad_users", 
        }
    }
    
    if $_add_adm_groups.size > 0 {
        $_add_adm_groups.each |$_group| {
           $_query_group = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                         'groupsManager', 'getGroupByName', {'name' => $_group, 'vo' => $vo}, $_group)
           $_group_id = $_query_group['id']
           perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                          'facilitiesManager', 'addAdmin', {'facility' => $_facility_id , 'authorizedGroup' => $_group_id}, 'nocache')
           perun_api_flushcache('facilitiesManager', 'getAdminGroups')        
        }
        notify{'addAdminGroups':
           message => "Adding admin groups: $_add_adm_groups",
        }
    }

    $_query_owners = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                    'facilitiesManager', 'getOwners', {'facility' => $_facility_id})

    $_owners = $_query_owners.map |$_owner| {
       $_owner['name']
    }

    $_add_owners = $owner - $_owners

    if $_add_owners.size > 0 {
       $_all_owners = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                        'ownersManager', 'getOwners', {})

       $_add_owner_ids = $_all_owners.filter |$_owner| {
          $_owner['name'] in $_add_owners 
       }.map |$_owner| {
          $_owner['id']
       }

       $_add_owner_ids.each |$_id| {
           perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                         'facilitiesManager', 'addOwner', {'facility' => $_facility_id, 'owner' => $_id}, 'nocache')
       }
       notify{'addOwners':
          message => "Adding owners: $_add_owners",
       }
       perun_api_flushcache('facilitiesManager', 'getOwners')
    }

    $_query_hosts = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                   'facilitiesManager', 'getHosts', {'facility' => $_facility_id})

    $_query_hostnames = $_query_hosts.map |$_host| {
       $_host['hostname']
    }

    if ! ($facts['fqdn'] in $_query_hostnames) {
       perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                      'facilitiesManager', 'addHost', {'facility' => $_facility_id, 'hostname' => $facts['fqdn']}, 'nocache')
       perun_api_flushcache('facilitiesManager', 'getHosts')
       notify{'addHost_self':
         message => "Adding host ${facts['fqdn']}",
       }
    }

    if $customhosts.size > 0 {
       $customhosts.each |$_host| {
          if ! ($_host in $_query_hostnames) {
              perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                             'facilitiesManager', 'addHost', {'facility' => $_facility_id, 'hostname' => $_host}, 'nocache')
              perun_api_flushcache('facilitiesManager', 'getHosts')
              notify{"addHost_$_host":
                 message => "Adding host ${_host}",
              }
          }
       }
    }

    $_dbhosts = puppetdb_query("resources{type = 'Perunapi::Host' and parameters.cluster = '$::clusterfullname'}").map |$_db_resource| {
       $_db_resource['parameters']['hostname']
    }

    $_live_hosts = concat($_dbhosts, $customhosts)

    $_remove_hosts = $_query_hostnames - $_live_hosts

    if $_remove_hosts.size > 0 {
       $_remove_hosts.each |$_remove_host| {
          $_hostid = $_query_hosts.filter |$_f_host| {
              $_f_host['hostname'] == $_remove_host
          }
          
          perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                         'facilitiesManager', 'removeHost', { "host" => $_hostid[0]['id'] }, 'nocache')
          notify{"removed${_hostid[0]['hostname']}":
            message => "Removed host ${_hostid[0]['hostname']} from facility $title",
          }
       }
       perun_api_flushcache('facilitiesManager', 'getHosts')
    }

    if $attributes.keys.size > 0 {
       $attributes.keys.each |$_attr| {
          if $_attr =~ /:facility:/ {
             $_attribute = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                          'attributesManager', 'getAttribute', {'facility' => $_facility_id, 'attributeName' => $_attr}, 
                                          $_attr)
             if $attributes[$_attr] == 'null' {
                $_newattr = undef
             } else { 
                $_newattr = $attributes[$_attr]
             }
             if $_attribute['id'] != undef and $_attribute['value'] != $_newattr {
                $_newval = {'value' => $_newattr}

                $_res = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                               'attributesManager', 'setAttribute', {'facility' => $_facility_id, 'attribute' => merge($_attribute, $_newval)}, 'nocache')
                if $_res != undef and $_res['errorId'] != undef and $_res['message'] != undef {
                   notify{"Cannot set attribute: $_attr. Reason: ${_res['message']}":}
                } else {
                   perun_api_flushcache('attributesManager', 'getAttribute', $_attr)
                   notify{"setAttribute_${_attr}":
                     message => "Setting attribute ${_attr} to value ${_newattr}.",
                  }
                }
             }
             if $_attribute['id'] == undef {
                notify{"Warning: undefined attribude name $_attr":}
             }
          }
       }
    }
  
    if $services.keys.size > 0 {
       $services.keys.each |$_service| {
          $_res = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                'servicesManager', 'getServiceByName', {'name' => $_service}, $_service)
          if $_res['errorId'] != undef and $_res['message'] != undef {
             fail("Cannot get service $_service id")
          }
          $_service_id = $_res['id']
          if $services[$_service]['destination'] == 'all' {
             $_destination = $facts['fqdn']
          } else {
             $_destination = $services[$_service]['destination']
          }
          $_dest_res = perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                                      'servicesManager', 'getDestinations', {'service' => $_service_id, 'facility' => $_facility_id}, $_service)
          $_assigned_dests = $_dest_res.map |$_dest| {
             $_dest['destination']
          }

          if !($_destination in $_assigned_dests) {
             if $services[$_service]['propagation'] != undef {
                $_propagation = $services[$_service]['propagation']
             } else {
                $_propagation = 'PARALLEL'
             }
             perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                           'servicesManager', 'addDestination', 
                           {'service' => $_service_id, 'facility' => $_facility_id, 'destination' => $_destination, 
                            'type' => $services[$_service]['type'], 'propagationType' => $_propagation}, 'nocache')
             perun_api_flushcache('servicesManager', 'getDestinations', $_service)
             notify{"addDestinations_${_service}":
               message => "Adding destination ${_destination} to service ${_service}",
             }
          }

          $_remove_dests = $_assigned_dests - $_live_hosts

          # remove only services on 'all' hosts, do not remove named hosts. hack for pbsmon_service
          if $_remove_dests.size > 0 and $services[$_service]['destination'] == 'all' {
             $_remove_dests.each |$_r_dest| {
                perun_api_call($::perunapi::perun_api_host, $::perunapi::perun_api_user, $::perunapi::perun_api_password,
                               'servicesManager', 'removeDestination',
                               {'service' => $_service_id, 'facility' => $_facility_id, 'destination' => $_r_dest,
                                'type' => $services[$_service]['type']}, 'nocache')
                notify{"removeDest${_r_dest}${_service_id}":
                  message => "Removed destination ${_r_dest} for service id ${_service}",
                }
             } 
             perun_api_flushcache('servicesManager', 'getDestinations', $_service)
          }
       }    
    }
  }
}
