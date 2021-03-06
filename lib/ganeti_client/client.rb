# The program makes use of the Google Ganeti RAPI to access diffrent resources. 
#
# The Client is mainly developed for usage with the Ganeti RAPI version 2
# 
# The protocol used is JSON over HTTP designed afther the REST principle. HTTP Basic authentication as per RFC2617 is 
# supported
#
# A few generic refered parameter types and the values they allow:
#   
#   bool:
#       A boolean option will accept 1 or 0 as numbers but not i.e. True or False
#
# A few parameter mean the same thing accross all resources which implement it:
#
#   bulk:
#       Bulk-mode means that for the resources which usually return just a list of child resources (e.g. /2/instances 
#       which returns just instance names), 
#       the output will instead contain detailed data for all these subresources. This is more efficient than query-ing 
#       the sub-resources themselves.
#
#   dry-run:
#       The boolean dry-run argument, if provided and set, signals to Ganeti that the job should not be executed, only 
#       the pre-execution checks will be done.
#       This is useful in trying to determine (without guarantees though, as in the meantime the cluster state could 
#       have changed) if the operation 
#       is likely to succeed or at least start executing.
#
#   force:
#       Force operation to continue even if it will cause the cluster to become inconsistent (e.g. because there are 
#       not enough master candidates).
#
# Author::    Michaël Rigart  (mailto:michael@netronix.be)
# Copyright:: Copyright (c) 2010 Michaël Rigart
# License::   Distributes under AGPL Licence

module Ganeti
 
    # This class contains all active resources available in Ganeti RAPI
    class Client

        attr_accessor :host, :username, :password, :version

        # Description:
        #   Create the client object
        # 
        # Parameters:
        #   string  host: hostname and port
        #   string  username: username that has access to RAPI
        #   string  password: password of the user provided
        def initialize(host, username, password)
            self.host = host
            self.username = username
            self.password = password
            
            self.version = self.version_get
        end

        # Description:
        #   Get the cluster information
        #
        # Return:
        #   GanetiInfo object
        def info_get
            url = get_url("info")
            response_body = send_request("GET", url)

            create_class("GanetiInfo")
 
            return GanetiInfo.new(response_body)
        end

        # Description:
        #   Redistrite configuration to all nodes
        # 
        # Return:
        #   string job id
        def redistribute_config
            url = get_url("redistribute-config")
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Get all instances on the cluster
        #
        # Parameters:
        #   boolean bulk (optional)
        #
        # Return:
        #   array of all available instances. The array items contain a GanetiInstance object
        def instances_get(bulk = 0)
            params =  {"bulk" => bulk}
            url = get_url("instances", params)
            response_body = send_request("GET", url)

            create_class("GanetiInstance")

            list = Array.new
            response_body.each { |item| list << GanetiInstance.new(item) }

            return list
        end

        # Description:
        #   Create an instance
        #   If the options bool dry-run argument is provided, the job will not be actually executed, only the 
        #   pre-execution checks will be done. 
        #   Query-ing the job result will return, in boty dry-run and normal case, the list of nodes selected for 
        #   the instance
        #
        #   Make sure the instance_name resolves!!
        #
        #   Build parameters dict, optional parameters need to be
        #   excluded to not cause issues with rapi.
        #  
        #   Example:
        #      info = {
        #              'hypervisor'    => 'kvm'    ,               'disk_template' => 'plain',
        #              'pnode'         => 'node.netronix.be',      'instance_name' => 'vm1.netronix.be',   
        #              'os'    => 'debootstrap+lucid',
        #              'name'          => 'vm1.netronix.be',
        #              'vcpus'         => '4',                     'memory'        => '4096',              
        #              'disks' => [25600],
        #              'kernel-path'   => '/boot/vmlinuz-2.6-kvmU'
        #             }
        #
        # Parameters:
        #   hash    info: hash of data needed for the instance creation (see above)
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job_id
        def instance_create(info, dry_run = 0)
            params = {
                        'hypervisor'    => info['hypervisor'],  'disk_template' => info['disk_template'],
                        'pnode'         => info['pnode'],       'instance_name' => info['instance_name'],   
                        'name'          => info['instance_name'],
                        'os'            => info['os'],          'vcpus'         => info['vcpus'],       
                        'memory'        => info['memory'],      'disks' => info['disks']
                    }

            # Add secondary node
            params['snode'] = info['snode'] if info['disk_template'] == 'drbd' && info['snode']

            # Add PVM parameters
            if info['hypervisor'] 
                params['kernel_path'] = info['kernel_path'] if info['kernel_path']
                params['initrd_path'] = info['initrd_path'] if info['initrd_path']
            end
            
            url = get_url("instances", {"dry-run" => dry_run})
            body = JSON.generate(params)
            response_body = send_request("POST", url, body)

            return response_body
        end

        # Description:
        #   Get instance specific information, similar to the bulk output from the instance list
        #
        # Parameters:
        #   string name: name of the instance
        #
        # Return
        #   GanetiInstance object
        def instance_get(name)
            url = get_url("instances/#{name}")
            response_body = send_request("GET", url)

            create_class("GanetiInstance")

            return GanetiInstance.new(response_body)
        end

        # Description:
        #   Delete a specific instance
        # 
        # Parameters:
        #   string  name: name of the instance
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_delete(name, dry_run = 0)
            params = {"dry-run" => dry_run}
            url = get_url("instances/#{name}", params)
            response_body = send_request("DELETE", url)

            return response_body 
        end

        # Description:
        #   Get detailed information about an instance. Static parameter can be set to return only static information 
        #   from the configuration without querying the instance's nodes
        #
        # Parameters:
        #   string      name: name of the instance
        #   boolean:    static (optional)
        #
        # Return:
        #   string job id
        def instance_get_info(name, static = 0)
            params = {"static" => static}
            url = get_url("instances/#{name}/info", params)
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Reboot a specific instance
        #   The URI takes optional type=soft|hard|full and ignore_secondaries=0|1 parameters
        # 
        #   type defines the reboot type. 
        #       soft is just a normal reboot, without terminating the hypervisor. 
        #       hard means full shutdown (including terminating the hypervisor process) and startup again
        #       full is like hard but also recreates the configuration from ground up as if you would have done 
        #       a gnt-instance shutdown and gnt-instance start on it
        #
        #
        # Parameters:
        #   string  name: name of the instance
        #   string  type: soft|hard|full (optional)
        #   boolean ignore_secondaries (optional)
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_reboot(name, type = "soft", ignore_secondaries = 0, dry_run = 0)
            params =  {"type" => type, "ignore_secondaries" => ignore_secondaries, "dry_run" => 0}
            url = get_url("instances/#{name}/reboot", params)
            response_body = send_request("POST", url)

            return response_body
        end


        # Description:
        #   Shutdown an instance
        # 
        # Parameters:
        #   string  name: name of the instance
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_shutdown(name, dry_run = 0)
            params = {"dry-run" => dry_run}
            url = get_url("instances/#{name}/shutdown", params)
            response_body = send_request("PUT", url)

            return response_body
        end      

        # Description:
        #   Startup an instance
        #   The URI takes an optional force=1|0 parameter to start the instance even if secondary disks are failing
        #
        # Parameters:
        #   string  name: name of the instance
        #   boolean force (optional)
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_startup(name, force = 0, dry_run=0)
            params = {"force" => force, "dry-run" => dry_run}
            url = get_url("instances/#{name}/startup", params)
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Install the operating system again
        # 
        # Parameters:
        #   string  name: name of the instance
        #   string  os_name: name of the os
        #   boolean nostartup (optional)
        #
        # Return:
        #   string job id
        def instance_reinstall(name, os_name, nostartup = 0)
            params = {"os" => os_name, "nostartup" => nostartup}
            url = get_url("instances/#{name}/reinstall", params)
            response_body = send_request("POST", url)

            return response_body
        end

        # Description:
        #   Replaces disks on an instance
        #   Takes the parameters mode (one of replace_on_primary, replace_on_secondary or replace_auto), disks 
        #   (comma seperated list of disk indexes), remote_node and iallocator
        #   Either remote_node or iallocator needs to be defined when using mode=replace_new_secondary
        #   mode is a mandatory parameter. replace_auto tries to determine the broken disk(s) on its own and 
        #   replacing it
        #
        # Parameters:
        #   string  name: name of the instance
        #   string  mode replace_on_primary|replace_on_secondary|replace_auto (optional)
        #   string  ialllocator:
        #   string  remote_node:
        #   string  disks: comma seperated list of disk indexes
        #
        # Return:
        #   string job id
        def instance_replace_disks(name, mode = "replace_auto", iallocator  = "", remote_node = "", disks = "")
            params = {"mode" => mode, "iallocator" => iallocator, "remote_node" => remote_node, "disks" => disks}
            url = get_url("instances/#{name}/replace-disks", params)
            response_body = send_request("POST", url)

            return response_body
        end

        # Description:
        #   Activate disks on an instance
        #   Takes the bool parameter ignore_size. When set ignore the recorded size (useful for forcing activation 
        #   when recoreded size is wrong)
        #
        # Parameters:
        #   string  name: name of the instance
        #   boolean ignore_size (optional)
        #
        # Return:
        #   string job id
        def instance_activate_disks(name, ignore_size = 0)
            params =  {"ignore_size" => ignore_size}
            url = get_url("instances/#{name}/activate-disks", params)
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Deactivate disks on an instance
        # 
        # Parameters:
        #   string name: name of the instance
        #
        # Return:
        #   string job id
        def instance_deactivate_disks(name)
            url = get_url("instances/#{name}/deactivate-disks")
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Returns a list of tags
        #
        #
        # Parameters:
        #   string name: name of the instance
        #
        # Return:
        #   array of tags
        def instance_get_tags(name)
            url = get_url("instances/#{name}/tags")
            response_body = send_request("GET", url)

            return response_body
        end
       
        # Description:
        #   Add a set of tags
        #
        # Parameters:
        #   string  name: name of the instance
        #   array   tags: Array of tags, tags are strings
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_create_tags(name, tags, dry_run = 0)
            params = {'dry-run' => dry_run, 'tag' => tags}
            url = get_url("instances/#{name}/tags", params)
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Delete (a) tag(s) on an instance
        # 
        # Parameters:
        #   string  name: name of the instance
        #   array   tags: Array of tags, tags are strings
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def instance_delete_tags(name, tags, dry_run = 0)
            params = {'dry-run' => dry_run, 'tag' => tags}
            url = get_url("instances/#{name}/tags", params)
            response_body = send_request("DELETE", url)

            return response_body
        end

        # Description:
        #   Returns a dictionary of jobs
        # 
        # Return:
        #   array of GanetiJob objects
        def jobs_get
            url = get_url("jobs")
            response_body = send_request("GET", url)
        
            create_class("GanetiJob")

            list = Array.new
            response_body.each { |item| list << GanetiJob.new(item) } 
            
            return list
        end      

        # Description:
        #   Individual job URI
        #   Return a job status
        #   Returns: a dictionary with job parameters
        #
        #   The result includes:
        #       id: job ID as number
        #       status: current job status as a string
        #       ops: involved OpCodes as a list of dictionaries for each opcodes in the job
        #       opstatus: OpCodes status as a list
        #       opresult: OpCodes results as a list
        #
        #   For a successful opcode, the opresult field corresponding to it will contain the raw result from its 
        #   LogicalUnit. In case an opcode has failed, its element in the opresult list will be a list of two 
        #   elements:
        #       first element the error type (the Ganeti internal error name)
        #       second element a list of either one or two elements:
        #       the first element is the textual error description
        #       the second element, if any, will hold an error classification
        # 
        #   The error classification is most useful for the OpPrereqError error type - these errors happen before 
        #   the OpCode has started executing, so it’s possible to retry the 
        #   OpCode without side effects. But whether it make sense to retry depends on the error classification:
        # 
        #       resolver_error
        #           Resolver errors. This usually means that a name doesn’t exist in DNS, so if it’s a case of 
        #           slow DNS propagation the operation can be retried later.
        #
        #       insufficient_resources
        #           Not enough resources (iallocator failure, disk space, memory, etc.). If the resources on the 
        #           cluster increase, the operation might succeed.
        #
        #       wrong_input
        #           Wrong arguments (at syntax level). The operation will not ever be accepted unless the arguments 
        #           change.
        #
        #       wrong_state
        #           Wrong entity state. For example, live migration has been requested for a down instance, or 
        #           instance creation on an offline node. The operation can be retried once the resource has 
        #           changed state.
        #   
        #       unknown_entity
        #           Entity not found. For example, information has been requested for an unknown instance.
        #
        #       already_exists
        #           Entity already exists. For example, instance creation has been requested for an 
        #           already-existing instance.
        #
        #       resource_not_unique
        #           Resource not unique (e.g. MAC or IP duplication).
        #    
        #       internal_error
        #           Internal cluster error. For example, a node is unreachable but not set offline, or the 
        #           ganeti node daemons are not working, etc. A gnt-cluster verify should be run.
        #    
        #       environment_error
        #           Environment error (e.g. node disk error). A gnt-cluster verify should be run.
        #
        #   Note that in the above list, by entity we refer to a node or instance, while by a resource we refer 
        #   to an instance’s disk, or NIC, etc.
        #
        # Parameters:
        #   string job_id
        #
        # Return:
        #   GanetiJob object
        def job_get(job_id)
            url = get_url("jobs/#{job_id}")
            response_body = send_request("GET", url)

            create_class("GanetiJob")

            return GanetiJob.new(response_body)
        end

        # Description:
        #   Cancel a not-yet-started job
        #
        # Parameters:
        #   string job_id: id of a job
        #
        # Return:
        #   string job id
        def job_delete(job_id)
            url = get_url("jobs/#{job_id}")
            response_body = send_request("DELETE", url)

            return response_body
        end

        # Description:
        #   Nodes resource
        #   Returns a list of all nodes
        #
        # Parameters:
        #   boolean: bulk (optional)
        #
        # Return:
        #   array of GanetiNode objects
        def nodes_get(bulk = 0)
            params = {"bulk", bulk}
            url = get_url("nodes", params)
            response_body = send_request("GET", url)

            create_class("GanetiNode")

            list = Array.new
            response_body.each { |item| list << GanetiNode.new(item) }

            return list 
        end

        # Description:
        #   Returns information about a node
        #
        # Parameters:
        #   string name: name of the node
        #
        # Return:
        #   GanetiNode object
        def node_get(name)
            url = get_url("nodes/#{name}")
            response_body = send_request("GET", url)

            create_class("GanetiNode")

            return GanetiNode.new(response_body)
        end

        # Description:
        #   Evacuates all secondary instances off a node.
        #   To evacuate a node, either one of the iallocator or remote_node parameters must be passed:
        #
        # Parameters:
        #   string name: name of the node
        #   string iallocator:
        #   string remote_node:
        #
        # Return:
        #   string job id
        def node_evaluate(name, iallocator = "", remote_node = "")
            params = {"iallocator" => iallocator, "remote_node" => remote_node}
            url = get_url("nodes/#{name}/evacuate", params) 
            response_body = send_request("POST", url)

           return response_body
        end

        # Description:
        #   Migrates all primary instances of a node
        #   No parameters are required, but the bool parameter live can be set to use live migration (if available)
        # 
        # Parameters:
        #   string  name: name of the node
        #   boolean live (optional)
        #
        # Return:
        #   string job id
        def node_migrate(name, live = 0)
            params = {"live" => live}
            url = get_url("nodes/#{name}/migrate", params)
            response_body = send_request("POST", url)

            return response_body
        end

        # Description:
        #   Get the node role
        #   Returns the current node role
        #
        #
        #   The rol is always one of the following:
        #       drained
        #       master
        #       master-candidate
        #       offline
        #       regular
        #
        # Parameters:
        #   string name: name of the node
        #
        # Return:
        #   node role as string
        def node_get_role(name)
            url = get_url("nodes/#{name}/role")
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Change the node role
        #   the request is a string which shoud be PUT to this URI. The result will be a job id
        #
        #   The rol is always one of the following:
        #       drained
        #       master
        #       master-candidate
        #       offline
        #       regular
        #
        # Parameters:
        #   string  name: name of the node
        #   string  role: name of the new role
        #   boolean force (optional)
        #
        # Return:
        #   string job id
        def node_change_role(name, role, force = 0)
            params = {"role" => role, "force" => force}
            url = get_url("nodes/#{name}/role", params)
            # This is again quirck in the RAPI. The string needs to have escaped 
            # quotes becouse of pythons "non-stric" JSON handling
            # http://code.google.com/p/ganeti/issues/detail?id=118
            body = "\"#{role}\""
            response_body = send_request("PUT", url, body)

            return response_body
        end

        # Description:
        #   Manages storage units on the node
        #   Requests a list of storage units on a node. Requires the parameters storage_type (one of file, lvm-pv 
        #   or lvm-vg) and output_fields. 
        #   The result will be a job id, using which the result can be retrieved
        #
        # Parameters:
        #   string name: name of the node
        #   string storage_type: name of the storage type
        #   string output_fields: fields it needs to return back
        # 
        # Return:
        #   string job id
        def node_get_storage(name, storage_type = "", output_fields = "")
            params = {"storage_type" => storage_type, "output_fields" => output_fields}
            url = get_url("nodes/#{name}/storage", params)
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Modify storage units on the node
        #   Mofifies parameters of storage units on the node. Requires the parameters storage_type (one of file, 
        #   lvm-pv or lvm-vg) and name (name of the storage unit). 
        #   Parameters can be passed additionally. Currently only allocatable (bool) is supported. 
        #
        # Parameters:
        #   string  name: name of the node
        #   string  storage_unit_name: name of the storage unit
        #   boolean allocatable (optional)
        # Return:
        #   string job id
        def node_modify_storage(name, storage_unit_name, storage_type, allocatable = 0)
            params = {"name" => storage_unit_name, "storage_type" => storage_type, "allocatable" => allocatable}
            url = get_url("nodes/#{name}/storage/modify", params)
            response_body = send_request("PUT", url)

            return response_body
        end


        # Description:
        #   Repairs a storage unit on the node. Requires the parameters storage_type (currently only lvm-vg can 
        #   be repaired) and name (name of the storage unit).
        #
        # Parameters:
        #   string name: name of the node
        #   string storage_name: name of the storage
        #   string storage_type: name of the storage type
        #
        # Return:
        #   string job id
        def node_repair_storage(name, storage_name, storage_type = "lvm-vg")
            params = {"storage_type" => storage_type, "name" => storage_name}
            url = get_url("nodes/#{name}/storage/repair", params)
            response_body = send_request("PUT", url)

            return response_body
        end


        # Description:
        #   Manages per-node tags
        #   Returns a list of tags
        #
        #
        # Parameters:
        #   string name: name of node
        # 
        # Return:
        #   array of tags, the tags are string
        def node_get_tags(name)
            url = get_url("nodes/#{name}/tags")
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Add a set of tags
        #   The request as a list of strings should be PUT to this URI.
        #
        #
        # Parameters:
        #   string  name: node name
        #   array   tags: Array of tags, tags are strings
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def node_create_tags(name, tags, dry_run = 0)
            params = {"tag" => tags, "dry-run" => dry_run}
            url = get_url("nodes/#{name}/tags", params)
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Deletes tags
        #   In order to delete a set of tags, the DELETE request should be addressed to URI like:
        #       /tags?tag=[tag]&tag=[tag]
        #
        #
        # Parameters:
        #   string name: node name
        #   array  tags: Array of tags, tags are strings
        #
        # Return:
        #   string job id
        def node_delete_tags(name, tags, dry_run = 0)
            params = {"tag" => tags, "dry-run" => dry_run}
            url = get_url("nodes/#{name}/tags", params)
            response_body = send_request("DELETE", url)

            return response_body
        end

        # Description:
        #   Returns a list of all OSes
        #   Can return error 500 in case of a problem. Since this is a costly operation for Ganeti 2.0, it is 
        #   not recommented to execute it too often
        #
        #   Example:
        #       ["debian-etch"]
        #
        # Return:
        #   array of os's, os is a string
        def os_list_get
            url = get_url("os")
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Manages cluster tags
        #   Returns the cluster tags
        #
        #   Example:
        #       ["tag1", "tag2", "tag3"]
        #
        # Return:
        #   array of tags, tags are strings
        def tags_get
            url = get_url("tags")
            response_body = send_request("GET", url)

            return response_body
        end

        # Description:
        #   Adds a set of tags
        #   The request as a list of strings should be PUT to this URI. The result will be a job id
        #
        # 
        # Parameters
        #   array   tags: Array of tags, tags are strings
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def tags_create(tags, dry_run = 0)
            params = {"tag" => tags, "dry-run" => dry_run}
            url = get_url("tags", params)
            response_body = send_request("PUT", url)

            return response_body
        end

        # Description:
        #   Deletes tags
        #   In order to delete a set of tags, the DELETE request should be addressed to URI like:
        #       /tags?tag=[tag]&tag=[tag]
        #
        #
        # Parameters:
        #   array   tags: Array of tags, tags are strings
        #   boolean dry_run (optional)
        #
        # Return:
        #   string job id
        def tags_delete(tags, dry_run = 0)
            params = {"tag" => tags, "dry-run" => dry_run}
            url = get_url("tags", params)
            response_body = send_request("DELETE", url)

            return response_body
        end


        # Description:
        #   The version resource
        #   This resource should be used to determine the remote API version and to adapt client accordingly
        #   Returns the remote API version. Ganeti 1.2 returns 1 and Ganeti 2.0 returns 2
        #
        # Return:
        #   string version number
        def version_get
            url = get_url("version")
            response_body = send_request("GET", url)
            
            return response_body
        end


        private

        # Description:
        #   Create the authentication headers, base64 encoded for basic auth
        #
        # Parameters:
        #   string username
        #   string password
        #
        # Return:
        #   hash headers
        def authenticate(username, password)
            basic = Base64.encode64("#{username}:#{password}").strip
            return {'Authorization' => "Basic #{basic}"}
        end
    
        # Descriptions:
        #   Create the url for the resource with extra parameters appended to the end if needed
        #
        # Params:
        #   string  path: path to the resource
        #   hash    params: extra parameters (optional)
        #
        # Return:
        #   string url 
        def get_url(path, params = nil)
            param_string = ""

            if params
                params.each do |key, value|
                    if value.kind_of?(Array)
                        value.each do |svalue|
                            param_string += "#{key}=#{svalue}&"
                        end
                    else
                        param_string += "#{key}=#{value}&"
                    end
                end
            end

            url =  (self.version)? "/#{self.version}/#{path}?#{param_string}" : "/#{path}?#{param_string}"
  
            return url.chop
        end

        # Description:
        #   Using the net::http library to create an http object that sends a request to the appropriate resource
        #   The response is catched, parsed and returned
        #
        # Parameters:
        #   string method: action method (get, post, put, delete)
        #   string url: the path to the resource
        #   string body: extra body information that needs to be send to the resource
        def send_request(method, url, body = nil, headers = {})
            raise ArgumentError, 'only GET, POST, PUT and DELETE methods are supported' unless %w[GET POST PUT DELETE].include?(method.to_s)
            raise ArgumentError, 'headers must be a hash' unless headers.is_a?(Hash)
            
            uri = URI.parse(host)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "http")? false : true
    
            headers.merge!({'User-Agent' => 'Ruby Ganeti RAPI Client'})
            headers.merge!(authenticate(self.username, self.password)) 

            begin
                response = http.send_request(method, url, body, headers)
            rescue => e
                puts "Error sending request"
                puts e.message
            else
                case response
                when Net::HTTPSuccess
                    parse_response(response.body.strip)
                else
                    response.instance_eval { class << self; attr_accessor :body_parsed; end }
                    begin 
                        response.body_parsed = parse_response(response.body) 
                    rescue
                        # raises  exception corresponding to http error Net::XXX
                        puts response.error! 
                    end
                end
            end
        end


        # Description:
        #   parse the response body to JSON
        #
        # Parameters:
        #   string response_body
        #
        # Return:
        #   json response: the reponse from the resource 
        def parse_response(response_body)
            # adding workaround becouse Google seems to operate on 'non-strict' JSON format
            # http://code.google.com/p/ganeti/issues/detail?id=117
            begin
                response_body = JSON.parse(response_body)
            rescue
                response_body = JSON.parse('['+response_body+']').first
            end

            return response_body
        end

        # Description:
        #   Create the appropriate Ganeti object if the class type does not exist yet.
        #   The specific Ganeti object inherits from a master object.
        #
        # Parameters:
        #   string class_name: name of the specific Ganeti object
        def create_class(class_name)
            unless(class_exists?(class_name))
                klass = Class.new Ganeti::GanetiObject
                Object.const_set(class_name, klass)
            end
        end

        # Description:
        #   Check if a specific class exists in the current runtime
        #
        # Parameters:
        #   string class_name: name of the specific Ganeti object
        #
        # Return:
        #   boolean
        def class_exists?(class_name)
            klass = Module.const_get(class_name)
            return klass.is_a?(Class)
        rescue NameError
            return false
        end
    end
end
