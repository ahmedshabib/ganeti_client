# The program makes use of the Google Ganeti RAPI to access diffrent resources. 
#
# The Client is mainly developed for usage with the Ganeti RAPI version 2
# 
# The protocol used is JSON over HTTP designed afther the REST principle. HTTP Basic authentication as per RFC2617 is supported
#
# A few generic refered parameter types and the values they allow:
#   
#   bool:
#       A boolean option will accept 1 or 0 as numbers but not i.e. True or False
#
# A few parameter mean the same thing accross all resources which implement it:
#
#   bulk:
#       Bulk-mode means that for the resources which usually return just a list of child resources (e.g. /2/instances which returns just instance names), 
#       the output will instead contain detailed data for all these subresources. This is more efficient than query-ing the sub-resources themselves.
#
#   dry-run:
#       The boolean dry-run argument, if provided and set, signals to Ganeti that the job should not be executed, only the pre-execution checks will be done.
#       This is useful in trying to determine (without guarantees though, as in the meantime the cluster state could have changed) if the operation 
#       is likely to succeed or at least start executing.
#
#   force:
#       Force operation to continue even if it will cause the cluster to become inconsistent (e.g. because there are not enough master candidates).
#
# Author::    Michaël Rigart  (mailto:michael@netronix.be)
# Copyright:: Copyright (c) 2010 Michaël Rigart
# License::   Distributes under AGPL Licence

module Ganeti
 
    # This class contains all active resources available in Ganeti RAPI
    class Client

        attr_accessor :host, :username, :password, :version, :show_response

        # Create the client object
        # 
        # Parameters:
        #   host: hostname and port
        #   username: username that has access to RAPI
        #   password: password of the user provided
        #   show_response: show response data (optional) 
        def initialize(host, username, password, show_response = false)
            self.host = host
            self.username = username
            self.password = password
            
            self.show_response = show_response

            self.version = self.version_get
        end


        # Get the cluster information
        #
        # Return:
        #   GanetiInfo object
        def info_get
            url = get_url("info")
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiInfo")
 
            return GanetiInfo.new(response_body)
        end

        # Redistrite configuration to all nodes
        # 
        # Return:
        #   job id.
        def redistribute_config
            url = get_url("redistribute-config")
            response_body = send_request("PUT", url)

            return response_body
        end

        # Get all instances on the cluster
        #
        # Parameters:
        #   bulk: 0|1 (optional)
        #
        # Return:
        #   Array of all available instances. The array items contain a GanetiInstance object
        def instances_get(bulk = 0)
            url = get_url("instances", {"bulk" => bulk})
            body = JSON.generate({"bulk" => bulk})
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiInstance")

            list = Array.new
            response_body.each { |item| list << GanetiInstance.new(item) }

            return list
        end

        # Create an instance
        # If the options bool dry-run argument is provided, the job will not be actually executed, only the pre-execution checks will be done. 
        # Query-ing the job result will return, in boty dry-run and normal case, the list of nodes selected for the instance
        #
        # Build parameters dict, optional parameters need to be
        # excluded to not cause issues with rapi.
        #  
        # Example:
        #      info = {
        #              'hypervisor'    => 'kvm'    ,               'disk_template' => 'plain',
        #              'pnode'         => 'node.netronix.be',      'name'          => 'vm1.netronix.be',   'os'    => 'debootstrap+lucid', 
        #              'vcpus'         => '4',                     'memory'        => '4096',              'disks' => [25600],
        #              'kernel-path'   => '/boot/vmlinuz-2.6-kvmU'
        #             }
        #
        # Parameters:
        #   info: hash of data needed for the instance creation
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   job_id
        def instance_create(info, dry_run = 0)
            params = {
                        'hypervisor'    => info['hypervisor'],  'disk_template' => info['disk_template'],
                        'pnode'         => info['pnode'],       'name'          => info['iname'],           'os'    => info['os'], 
                        'vcpus'         => info['vcpus'],       'memory'        => info['memory'],          'disks' => info['disks']
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

        # Get instance specific information, similar to the bulk output from the instance list
        #
        # Parameters:
        #   name: name of the instance
        #
        # Return
        #   GanetiInstance object
        def instance_get(name)
            url = get_url("instances/#{name}")
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiInstance")

            return GanetiInstance.new(response_body)
        end

        # Delete a specific instance
        # 
        # Parameters:
        #   name: name of the instance
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   ?
        def instance_delete(name, dry_run = 0)
            url = get_url("instances/#{name}", {"dry-run" => dry_run})
            response_body = send_request("DELETE", url)

            return response_body 
        end

        # Get detailed information about an instance. Static parameter can be set to return only static information from the configuration without querying the instance's nodes
        #
        # Parameters:
        #   name: name of the instance
        #   static: 0|1 (optional)
        #
        # Return:
        #   job id
        def instance_get_info(name, static = 0)
            url = get_url("instances/#{name}/info", {"static" => static})
            response_body = send_request("GET", url)

            return response_body
        end

        # Reboot a specific instance
        # The URI takes optional type=soft|hard|full and ignore_secondaries=0|1 parameters
        # 
        # type defines the reboot type. 
        #   soft is just a normal reboot, without terminating the hypervisor. 
        #   hard means full shutdown (including terminating the hypervisor process) and startup again
        #   full is like hard but also recreates the configuration from ground up as if you would have don a gnt-instance shutdown and gnt-instance start on it
        #
        # it supports the dry-run argument
        #
        # Parameters:
        #   name: name of the instance
        #   type: soft|hard|full (optional)
        #   ignore_secondaries: 0|1 (optional)
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   job id
        def instance_reboot(name, type = "soft", ignore_secondaries = 0, dry_run = 0)
            url = get_url("instances/#{name}/reboot", {"type" => type, "ignore_secondaries" => ignore_secondaries, "dry_run" => 0})
            response_body = send_request("POST", url)

            return response_body
        end


        # Shutdown an instance
        # 
        # Parameters:
        #   name: name of the instance
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   job id
        def instance_shutdown(name, dry_run = 0)
            url = get_url("instances/#{name}/shutdown", {"dry-run" => dry_run})
            response_body = send_request("PUT", url)

            return response_body
        end      

        # Startup an instance
        # The URI takes an optional force=1|0 parameter to start the instance even if secondary disks are failing
        #
        # Parameters:
        #   name: name of the instance
        #   force: 0|1 (optional)
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   job id
        def instance_startup(name, force = 0, dry_run=0)
            url = get_url("instances/#{name}/startup", {"force" => force, "dry-run" => dry_run})
            response_body = send_request("PUT", url)

            return response_body
        end

        # Install the operating system again
        # 
        # Parameters:
        #   name: name of the instance
        #   os_name: name of the os
        #   nostartup: 0|1 (optional)
        #
        # Return:
        #   ?
        def instance_reinstall(name, os_name, nostartup = 0)
            url = get_url("instances/#{name}/reinstall", {"os" => os_name, "nostartup" => nostartup})
            response_body = send_request("POST", url)

            return response_body
        end

        # Replaces disks on an instance
        # Takes the parameters mode (one of replace_on_primary, replace_on_secondary or replace_auto), disks (comma seperated list of disk indexes), remote_node and iallocator
        # Either remote_node or iallocator needs to be defined when using mode=replace_new_secondary
        # mode is a mandatory parameter. replace_auto tries to determine the broken disk(s) on its own and replacing it
        #
        # Parameters:
        #   name: name of the instance
        #   mode replace_on_primary|replace_on_secondary|replace_auto (optional)
        #   ialllocator:
        #   remote_node:
        #   disks: comma seperated list of disk indexes
        #
        # Return:
        #   ?
        def instance_replace_disks(name, mode = "replace_auto", iallocator  = "", remote_node = "", disks = "")
            url = get_url("instances/#{name}/replace-disks", {"mode" => mode, "iallocator" => iallocator, "remote_node" => remote_node, "disks" => disks})
            response_body = send_request("POST", url)

            return response_body
        end

        # Activate disks on an instance
        # Takes the bool parameter ignore_size. When set ignore the recorded size (useful for forcing activation when recoreded size is wrong)
        #
        # Parameters:
        #   name: name of the instance
        #   ignore_size: 0|1 (optional)
        #
        # Return:
        #   ?
        def intance_activate_disks(name, ignore_size = 0)
            url = get_url("instances/#{name}/activate-disks", {"ignore_size" => ignore_size})
            response_body = send_request("PUT", url)

            return response_body
        end

        # Deactivate disks on an instance
        # 
        # Parameters:
        #   name: name of the instance
        #
        # Return:
        #   ?
        def instance_deactivate_disks(name)
            url = get_url("instances/#{name}/deactivate-disks")
            response_body = send_request("PUT", url)

            return response_body
        end

        # Returns a list of tags
        #
        # Parameters:
        #   name: name of the instance
        #
        # Return:
        #   Array of tags
        def instance_get_tags(name)
            url = get_url("instances/#{name}/tags")
            response_body = JSON.parse(send_request("GET", url))

            return response_body
        end
       
        # Add a set of tags
        #
        # Parameters:
        #   name: name of the instance
        #   tags: Array of tags
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   job id
        def instance_create_tags(name, tags, dry_run = 0)
            url = get_url("instances/#{name}/tags")
            body = JSON.generate({'tag' => 'tag1', 'tag' => 'tag2', 'dry-run' => dry_run})
            response_body = send_request("PUT", url, body)

            return response_body
        end

        # Delete (a) tag(s) on an instance
        # 
        # Parameters:
        #   name: name of the instance
        #   tags: Array of tags
        #   dry_run: 0|1 (optional)
        #
        # Return:
        #   ?
        def instance_delete_tags(name, tags, dry_run = 0)
            url = get_url("instances/#{name}/tags", {"tags" => tags, "dry-run" => dry_run})
            response_body = send_request("DELETE", url)

            return response_body
        end

        # Returns a dictionary of jobs
        # 
        # Return:
        #   Array of GanetiJob objects
        def jobs_get
            url = get_url("jobs")
            response_body = JSON.parse(send_request("GET", url))
        
            create_class("GanetiJob")

            list = Array.new
            response_body.each { |item| list << GanetiJob.new(item) } 
            
            return list
        end      

        # Individual job URI
        # Return a job status
        # Returns: a dictionary with job parameters
        #
        # The result includes:
        #   id: job ID as number
        #   status: current job status as a string
        #   ops: involved OpCodes as a list of dictionaries for each opcodes in the job
        #   opstatus: OpCodes status as a list
        #   opresult: OpCodes results as a list
        #
        # For a successful opcode, the opresult field corresponding to it will contain the raw result from its LogicalUnit. In case an opcode has failed, its element in the opresult list will be a list of two elements:
        #   first element the error type (the Ganeti internal error name)
        #   second element a list of either one or two elements:
        #   the first element is the textual error description
        #   the second element, if any, will hold an error classification
        # 
        # The error classification is most useful for the OpPrereqError error type - these errors happen before the OpCode has started executing, so it’s possible to retry the 
        # OpCode without side effects. But whether it make sense to retry depends on the error classification:
        # 
        #   resolver_error
        #       Resolver errors. This usually means that a name doesn’t exist in DNS, so if it’s a case of slow DNS propagation the operation can be retried later.
        #
        #   insufficient_resources
        #       Not enough resources (iallocator failure, disk space, memory, etc.). If the resources on the cluster increase, the operation might succeed.
        #
        #   wrong_input
        #       Wrong arguments (at syntax level). The operation will not ever be accepted unless the arguments change.
        #
        #   wrong_state
        #       Wrong entity state. For example, live migration has been requested for a down instance, or instance creation on an offline node. The operation can be retried once the resource has changed state.
        #   
        #   unknown_entity
        #       Entity not found. For example, information has been requested for an unknown instance.
        #
        #   already_exists
        #       Entity already exists. For example, instance creation has been requested for an already-existing instance.
        #
        #   resource_not_unique
        #       Resource not unique (e.g. MAC or IP duplication).
        #    
        #   internal_error
        #       Internal cluster error. For example, a node is unreachable but not set offline, or the ganeti node daemons are not working, etc. A gnt-cluster verify should be run.
        #    
        #   environment_error
        #       Environment error (e.g. node disk error). A gnt-cluster verify should be run.
        #
        # Note that in the above list, by entity we refer to a node or instance, while by a resource we refer to an instance’s disk, or NIC, etc.
        def job_get(job_id)
            url = get_url("jobs/#{job_id}")
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiJob")

            return GanetiJob.new(response_body)
        end

        # Cancel a not-yet-started job
        #
        # Parameters:
        #   job_id: id of a job
        #
        # Return:
        #   ?
        def job_delete(job_id)
            url = get_url("jobs/#{job_id}")
            response_body = send_request("DELETE", url)

            return response_body
        end

        # Nodes resource
        # Returns a list of all nodes
        # If the optional ‘bulk’ argument is provided and set to ‘true’ value (i.e ‘?bulk=1’).
        #
        # Returns detailed information about nodes as a list.
        def nodes_get(bulk = 0)
            url = get_url("nodes", {"bulk", bulk})
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiNode")

            list = Array.new
            response_body.each { |item| list << GanetiNode.new(item) }

            return list 
        end

        # Returns information about a node
        def node_get(name)
            url = get_url("nodes/#{name}")
            response_body = JSON.parse(send_request("GET", url))

            create_class("GanetiNode")

            return GanetiNode.new(response_body)
        end

        # Evacuates all secondary instances off a node.
        # To evacuate a node, either one of the iallocator or remote_node parameters must be passed:
        #
        # Example:
        #   evacuate?iallocator=[iallocator]
        #   evacuate?remote_node=[nodeX.example.com]
        #
        # Return:
        #   job id
        def node_evaluate(name, iallocator = "", remote_node = "")
           url = get_url("nodes/#{name}/evacuate", {"iallocator" => iallocator, "remote_node" => remote_node}) 
           response_body = send_request("POST", url)

           return response_body
        end

        # Migrates all primary instances of a node
        # No parameters are required, but the bool parameter live can be set to use live migration (if available)
        # 
        # Example:
        #   migrate?live=[0|1]
        def node_migrate(name, live = 0)
            url = get_url("nodes/#{name}/migrate", {"live" => live})
            response_body = send_request("POST", url)

            return response_body
        end

        # Get the node role
        # Returns the current node role
        #
        # Example:
        #   "master-candidate"
        #
        # The rol is always one of the following:
        #   drained
        #   master
        #   master-candidate
        #   offline
        #   regular
        def node_get_role(name)
            url = get_url("nodes/#{name}/role")
            response_body = send_request("GET", url)

            return response_body
        end

        # Change the node role
        # the request is a string which shoud be PUT to this URI. The result will be a job id
        # It supports the bool force argument
        #
        # The rol is always one of the following:
        #   drained
        #   master
        #   master-candidate
        #   offline
        #   regular
        def node_change_role(name, role, force = 0)
            url = get_url("nodes/#{name}/role", {"role" => role, "force" => foce})
            response_body = send_request("PUT", url)

            return response_body
        end

        # Manages storage units on the node
        # Requests a list of storage units on a node. Requires the parameters storage_type (one of file, lvm-pv or lvm-vg) and output_fields. The result will be a job id, using which the result can be retrieved
        def node_get_storage(name, storage_type = "", output_fields = "")
            url = get_url("nodes/#{name}/storage", {"storage_type" => storage_type, "output_fields" => output_fields})
            response_body = send_request("GET", url)

            return response_body
        end

        # Modify storage units on the node
        # Mofifies parameters of storage units on the node. Requires the parameters storage_type (one of file, lvm-pv or lvm-vg) and name (name of the storage unit). 
        # Parameters can be passed additionally. Currently only allocatable (bool) is supported. 
        #
        # The result will be a job id.
        def node_modify_storage(name, storage_type, allocatable = 0)
            url = get_url("nodes/#{name}/storage/modify", {"storage_type" => storage_type, "allocatable" => allocatable})
            response_body = send_request("PUT", url)

            return response_body
        end


        # Repairs a storage unit on the node. Requires the parameters storage_type (currently only lvm-vg can be repaired) and name (name of the storage unit).
        #
        # The result will be a job id
        def node_repair_storage(name, storage_type = "lvm-vg")
            url = get_url("nodes/#{name}/storage/repair", {"storage_type" => storage_type})
            reponse_body = send_request("PUT", url)

            return response_body
        end


        # Manages per-node tags
        # Returns a list of tags
        #
        # Example:
        #   ["tag1","tag2", "tag3"]
        #
        # Return:
        #   array of tags
        def node_get_tags(name)
            url = get_url("nodes/#{name}/tags")
            response_body = send_request("GET", url)

            return response_body
        end

        # Add a set of tags
        # The request as a list of strings should be PUT to this URI.
        # It supports the dry-run argument
        #
        # The result will be a job id
        def node_create_tags(name, tags, dry_run = 0)
            url = get_url("nodes/#{name}/tags", {"tags" => tags, "dry-run" => dry_run})
            response_body = send_request("PUT", url)

            return response_body
        end

        # Deletes tags
        # In order to delete a set of tags, the DELETE request should be addressed to URI like:
        #   /tags?tag=[tag]&tag=[tag]
        #
        # It supports the dry-run argument
        def node_delete_tags(name, tags, dry_run = 0)
            url = get_url("nodes/#{name}/tags", {"tags" => targs, "dry-run" => dry_run})
            response_body = send_request("DELETE", url)

            return response_body
        end

        # OS resource
        # Returns a list of all OSes
        # 
        # Can return error 500 in case of a problem. Since this is a costly operation for Ganeti 2.0, it is not recommented to execute it too often
        #
        # Example:
        #   ["debian-etch"]
        def os_list_get
            url = get_url("os")
            response_body = JSON.parse(send_request("GET", url))

            return response_body
        end

        # Manages cluster tags
        # Returns the cluster tags
        #
        # Example:
        #   ["tag1", "tag2", "tag3"]
        def tags_get
            url = get_url("tags")
            response_body = JSON.parse(send_request("GET", url))

            return response_body
        end

        # Adds a set of tags
        # The request as a list of strings should be PUT to this URI. The result will be a job id
        #
        # It supports the dry-run argument
        def tags_create(tags, dry_run = 0)
            url = get_url("tags", {"tags" => tags, "dry-run" => dry_run})
            response_body = send_request("PUT", url)

            return response_body
        end

        # Deletes tags
        # In order to delete a set of tags, the DELETE request should be addressed to URI like:
        #   /tags?tag=[tag]&tag=[tag]
        #
        # It supports the dry-run argument
        def tags_delete(tags, dry_run = 0)
            url = get_url("tags", {"tags" => tags, "dry-run" => dry_run})
            response_body = send_request("DELETE", url)

            return response_body
        end


        # The version resource
        # This resource should be used to determine the remote API version and to adapt client accordingly
        # Returns the remote API version. Ganeti 1.2 returns 1 and Ganeti 2.0 returns 2
        def version_get
            url = get_url("version")
            response_body = send_request("GET", url)
            
            return response_body
        end


        private

        def authenticate(username, password)
            basic = Base64.encode64("#{username}:#{password}").strip
            headers = {'Authorization' => "Basic #{basic}"}
      
            return headers         
        end
    
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

        def send_request(method, url, body = nil)
            uri = URI.parse(host)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == "http")? false : true

            headers = {}
            headers = authenticate(self.username, self.password) if method != 'GET'

            response = http.send_request(method, url, body, headers)


            puts "Response #{response.code} #{response.message}: #{response.body}" if self.show_response

            return response.body.strip
        end

        def create_class(class_name)
            unless(class_exists?(class_name))
                klass = Class.new Ganeti::GanetiObject
                Object.const_set(class_name, klass)
            end
        end

        def class_exists?(class_name)
            klass = Module.const_get(class_name)
            return klass.is_a?(Class)
        rescue NameError
            return false
        end
    end
end
