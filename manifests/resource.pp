define perunapi::resource (
       $ensure     = 'present',
  Hash $resource   = {},
  String $facility = '',
  Hash $attributes = {},
  Hash $services   = {},
) {

  if $ensure == 'present' {

    $_query_fa = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                               'facilitiesManager', 'getFacilityByName', {'name' => $facility}, $facility)

    if $_query_fa['id'] != undef {
       $_facility_id = $_query_fa['id']
    } else {
       fail("No facility named ${facility}")
    }

    $_query_vo = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                'vosManager', 'getVoByShortName', {'shortName' => $resource['vo']}, $resource['vo'])

    if $_query_vo['id'] != undef {
       $_vo_id = $_query_vo['id']
    } else {
       fail("No VO named ${resource['vo']}")
    }
  
    $_query_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                 'resourcesManager', 'getResourceByName', {'vo' => $_vo_id, 'facility' => $_facility_id,
                                                                           'name' => $resource['name']}, 
                                                                           "${_vo_id}-${_facility_id}-${resource['name']}")

    if $_query_res['id'] == undef {
       $_create_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                     'resourcesManager', 'createResource', 
                                     {'resource' => {'name' => $resource['name'], 'description' => $resource['description']},
                                      'vo' => $_vo_id, 'facility' => $_facility_id}, 'nocache')
       perun_api_flushcache('resourcesManager', 'getResourceByName', "${_vo_id}-${_facility_id}-${resource['name']}")

       $_resource_id = $_create_res['id']

       notify{"createResource${resource['name']}${resource['vo']}":
         message => "created resource ${resource['name']} for VO ${resource['vo']}",
       }
    } else {
       $_resource_id = $_query_res['id']
    }

    if $resource['tags'] != undef {
       $_query_tags = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                       'resourcesManager', 'getAllResourcesTagsForResource', {'resource' => $_resource_id}, $_resource_id)
       $_tags_name = $_query_tags.map |$_tag_obj| {
          $_tag_obj['tagName']
       }
       
       $_query_all_tags = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                        'resourcesManager', 'getAllResourcesTagsForVo', {'vo' => $_vo_id}, $resource['vo'])
       
       $resource['tags'].each |$_tag| {
          if !($_tag in $_tags_name) {
             $_tag_obj = $_query_all_tags.filter |$_t| {
                 $_t['tagName'] == $_tag
             }
             if $_tag_obj == undef {
                fail("Unknown tag: $_tag")
             }
             $_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                    'resourcesManager', 'assignResourceTagToResource', {'resourceTag' => $_tag_obj[0], 'resource' => $_resource_id}, 'nocache')
             perun_api_flushcache('resourcesManager', 'getAllResourcesTagsForResource', $_resource_id)
             notify{"setTagForResource${_resource_id}${_tag}":
                message => "assigned resource tag ${_tag} to resource ${resource['name']}",
             }
          }
       }
    }

    if $attributes.keys.size > 0 {
       $_pending_a = perun_api_callback($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                        'setAttribute')
       if $_pending_a != undef and $_pending_a['endTime'] == -1 {
          notify{"setAttributeTimeout${_resource_id}":
            message => "Pending set attribute request. Giving up.",
          }
          return()
       }

       $attributes.keys.each |$_attr| {
          if $_attr =~ /:resource:/ {

             $_attribute = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                          'attributesManager', 'getAttribute', {'resource' => $_resource_id, 'attributeName' => $_attr},
                                           $_attr)
             if $attributes[$_attr] == 'null' {
                $_newattr = undef
             } else {
                $_newattr = $attributes[$_attr]
             }
             if $_attribute['id'] != undef and $_attribute['value'] != $_newattr {
                $_newval = {'value' => $_newattr}
                $_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                               'attributesManager', 'setAttribute', {'resource' => $_resource_id, 
                                                                     'attribute' => merge($_attribute, $_newval)}, 'nocache')

                perun_api_flushcache('attributesManager', 'getAttribute', $_attr)

                if $_res != undef and $_res['timeout'] == true {
                   notify{"setAttribute_${_attr}_timeout":
                     message => "Setting attribute ${_attr} to value ${_newattr}. Stopping setting more attributes.",
                   }
                   return()
                }

                if $_res != undef and $_res['errorId'] != undef and $_res['message'] != undef {
                   fail("Cannot set attribute: $_attr. Reason: ${_res['message']}")
                } else {
                   notify{"setAttribute_${_attr}${_resource_id}":
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
       $_pending_s = perun_api_callback($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                        'assignService')
       if $_pending_s != undef and $_pending_s['endTime'] == -1 {
          notify{"assignServicesTimeout${_resource_id}":
            message => "Pending assign service request. Giving up.",
          }
          return()
       }

       $services.keys.each |$_service| {
          if $resource['name'] in $services[$_service]['resources'] {

              $_services_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                             'resourcesManager', 'getAssignedServices', {'resource' => $_resource_id}, $_resource_id)

              $_services_list = $_services_res.map |$_s| {
                 $_s['name']
              }
 
              if !($_service in $_services_list) {
                 $_res = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                        'servicesManager', 'getServiceByName', {'name' => $_service}, $_service)
                 if $_res['errorId'] != undef and $_res['message'] != undef {
                    fail("Cannot get service $_service id")
                 }
                 $_service_id = $_res['id']

                 $_assign_resp = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                                'resourcesManager', 'assignService', {'resource' => $_resource_id, 'service' => $_service_id}, 'nocache')
 
                 perun_api_flushcache('resourcesManager', 'getAssignedServices', $_resource_id)

                 if $_assign_resp != undef and $_assign_resp['timeout'] == true {
                    notify{"assignService${_service}${_resource_id}_timeout":
                      message => "Assigned service ${_service} to resource ${resource['name']} timeout. Stopping assigning more services.",
                    }
                    return()
                 }
 
                 notify{"assignService${_service}${_resource_id}":
                    message => "assigned service ${_service} to resource ${resource['name']}\n$_assign_resp",
                 }
              }
          }
       }
    }

    if $resource['groupsfromresource'] != undef {
       $_pending_g = perun_api_callback($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                        'assignGroupsToResource')
       if $_pending_g != undef and $_pending_g['endTime'] == -1 {
          notify{"assignGroupsTimeout_${resource['groupsfromresource']}":
            message => "Pending assign groups request. Giving up.",
          }
          return()
       }

       $_query_src = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                    'resourcesManager', 'getAssignedGroups', { 'resource' => $resource['groupsfromresource'] }, 'nocache')

       if $_query_src != undef and $_query_src =~ Hash and $_query_src['errorId'] != undef and $_query_src['message'] != undef {
          fail("Cannot query source resource ${resource['groupsfromresource']} for groups. ${_query_src}")
       }

       $_query_dst = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                    'resourcesManager', 'getAssignedGroups', { 'resource' => $_resource_id }, $_resource_id)

       $_add_groups = $_query_src - $_query_dst

       if $_add_groups.size > 0 {
         $_add_g_ids = $_add_groups.map |$_gr| {
           $_gr['id']
         }

         $_res_gr = perun_api_call($perunapi::perun_api_host, $perunapi::perun_api_user, $perunapi::perun_api_password,
                                   'resourcesManager', 'assignGroupsToResource', {'resource' => $_resource_id, 'groups' => $_add_g_ids}, 'nocache')

         perun_api_flushcache('resourcesManager', 'getAssignedGroups', $_resource_id)
         if $_res_gr != undef and $_res_gr['timeout'] == true {
           notify{"assignGroupsToResource_timeout_${_resource_id}":
             message => "assign groups to resource ${resource['name']} timeout. Giving up",
           }
           return()
         }
     
         notify{"assignGroupsToResource${_resource_id}":
            message => "assigned $_add_g_ids groups to resource ${resource['name']}\n${_res_gr}",
         }
       }
    }
  }
}
