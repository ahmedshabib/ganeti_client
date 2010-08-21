require File.join(File.dirname(__FILE__), 'test_helper')

class ClientTest < Test::Unit::TestCase
    include Ganeti

    
    context "A client instance" do
        setup do
           @data = YAML.load_file('fixtures/personal.yml')
            @client = Ganeti::Client.new(@data['login']['host'], @data['login']['user'], @data['login']['password'])
        end

        should "be kind of Client" do
            assert_kind_of Ganeti::Client, @client
        end

        should "return a GanetiInfo object" do
            assert_equal @client.info_get.class.to_s, 'GanetiInfo'
        end

        should "return String" do
            name = 'netronix.be'
            assert_kind_of String, @client.redistribute_config
            assert_kind_of String, @client.instance_delete(@data['instance']['name'], @data['instance']['dry-run'])
            assert_kind_of String, @client.instance_get_info(@data['instance']['name'], @data['instance']['static'])
            assert_kind_of String, @client.instance_reboot(@data['instance']['name'], @data['instance']['type'], @data['instance']['ignore-secondaries'], @data['instance']['dry-run'])
            assert_kind_of String, @client.instance_shutdown(@data['instance']['name'], @data['instance']['dry-run'])
            assert_kind_of String, @client.instance_startup(@data['instance']['name'], @data['instance']['force'], @data['instance']['dry-run'])
            assert_kind_of String, @client.instance_reinstall(@data['instance']['name'], @data['instance']['os'], @data['instance']['nostartup'])
            assert_kind_of String, @client.instance_replace_disks(@data['instance']['name'], @data['instance']['mode'], @data['instance']['iallocator'], @data['instance']['remote-node'], @data['instance']['disks'])
            assert_kind_of String, @client.instance_activate_disks(@data['instance']['name'], @data['instance']['ignore-size'])
            assert_kind_of String, @client.instance_deactivate_disks(@data['instance']['name'])
            assert_kind_of String, @client.instance_create_tags(@data['instance']['name'], @data['tags'], @data['instance']['dry-run'])
            assert_kind_of String, @client.instance_delete_tags(@data['instance']['name'], @data['tags'], @data['instance']['dry-run'])
            assert_kind_of String, @client.job_delete(job_id)
            assert_kind_of String, @client.node_evaluate(@data['node']['name'], @data['node']['iallocator'], @data['node']['remote-node'])
            assert_kind_of String, @client.node_migrate(@data['node']['name'], @data['node']['live'])
            assert_kind_of String, @client.node_get_role(@data['node']['name'])
            assert_kind_of String, @client.node_change_role(@data['node']['name'], @data['node']['role'], @data['node']['force'])
            assert_kind_of String, @client.node_get_storage(@data['node']['name'], @data['node']['storage-type'], @data['node']['output-fields'])
            assert_kind_of String, @client.node_modify_storage(@data['node']['name'], @data['node']['storage-unit-name'], @data['node']['storage-type'], @data['node']['allocatable'])
            assert_kind_of String, @client.node_repair_storage(@data['node']['name'], @data['node']['storage-name'], @data['node']['storage-type'])
            assert_kind_of String, @client.node_create_tags(@data['node']['name'], @data['general']['tags'], @data['node']['dry-run'])
            assert_kind_of String, @client.node_delete_tags(@data['node']['name'], @data['general']['tags'], @data['node']['dry-run'])
            assert_kind_of String, @client.tags_create(@data['general']['tags'], @data['general']['dry-run'])
            assert_kind_of String, @client.tags_delete(@data['general']['tags'], @data['general']['dry-run'])
            assert_kind_of String, @client.version_get
        end

        should "return an Array of GanetiInstance" do
            instances = @client.instances_get
            assert_kind_of Array, instances

            instances.each do |instance|
                assert_equal instance.class.to_s, 'GanetiInstance'
            end
        end

        should "return object id of String" do
            assert_kind_of String, @client.instance_create(@data['instance']['info'])
        end

        should "return a GanetiInstance object" do
            name = "netronix.be"
            assert_equal @client.instance_get(@data['instance']['name']).class.to_s, 'GanetiInstance'
        end

        should "return an Array of Strings" do
            array = @client.instance_get_tags(@data['instance']['name'])
            assert_kind_of Array, array

            array.each do |item|
                assert_kind_of String, item
            end

            array = @client.node_get_tags(@data['node']['name'])
            assert_kind_of Array, array

            array.each do |item|
                assert_kind_of String, item
            end

            array = @client.os_list_get
            assert_kind_of Array, array

            array.each do |item|
                assert_kind_of String, item
            end

            array = @client.tags_get
            assert_kind_of Array, array

            array.each do |item|
                assert_kind_of String, item
            end
        end

        should "return an Array of GanetiJob objects" do
            jobs = @client.jobs_get
            assert_kind_of Array, jobs

            jobs.each do |job|
                assert_equal job.class.to_s, 'GanetiJob'
            end
        end

        should "return a GanetiJob object" do
            assert_equal @client.job_get(@data['general']['job-id']).class.to_s, 'GanetiJob'
        end

        should "return an Array of GanetiNode objects" do
            nodes = @client.nodes_get
            assert_kind_of Array, nodes

            nodes.each do |node|
                assert_equal node.class.to_s, 'GanetiNode'
            end
        end

        should "return a GanetiNode object" do
            assert_equal @client.node_get(@data['node']['name']), 'GanetiNode'
        end
    end
end
