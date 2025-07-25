# frozen_string_literal: true

require "aws-sdk-ec2"
class Prog::Aws::Instance < Prog::Base
  subject_is :vm

  label def start
    public_keys = (vm.sshable.keys.map(&:public_key) + (vm.project.get_ff_vm_public_ssh_keys || [])).join("\n")
    # Define user data script to set a custom username
    user_data = <<~USER_DATA
#!/bin/bash
custom_user="#{vm.unix_user}"
# Create the custom user
adduser $custom_user --disabled-password --gecos ""
# Add the custom user to the sudo group
usermod -aG sudo $custom_user
# disable password for the custom user
echo "$custom_user ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$custom_user
# Set up SSH access for the custom user
mkdir -p /home/$custom_user/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/$custom_user/.ssh/
chown -R $custom_user:$custom_user /home/$custom_user/.ssh
chmod 700 /home/$custom_user/.ssh
chmod 600 /home/$custom_user/.ssh/authorized_keys
echo #{public_keys.shellescape} > /home/$custom_user/.ssh/authorized_keys
usermod -L ubuntu
    USER_DATA

    instance_response = client.run_instances({
      image_id: vm.boot_image, # AMI ID
      instance_type: Option.aws_instance_type_name(vm.family, vm.vcpus),
      block_device_mappings: [
        {
          device_name: "/dev/sda1",
          ebs: {
            encrypted: true,
            delete_on_termination: true,
            iops: 3000,
            volume_size: 40,
            volume_type: "gp3",
            throughput: 125
          }
        }
      ],
      network_interfaces: [
        {
          network_interface_id: vm.nics.first.nic_aws_resource.network_interface_id,
          device_index: 0
        }
      ],
      private_dns_name_options: {
        hostname_type: "ip-name",
        enable_resource_name_dns_a_record: false,
        enable_resource_name_dns_aaaa_record: false
      },
      min_count: 1,
      max_count: 1,
      user_data: Base64.encode64(user_data),
      tag_specifications: Util.aws_tag_specifications("instance", vm.name),
      client_token: vm.id
    })
    instance_id = instance_response.instances[0].instance_id
    subnet_id = instance_response.instances[0].network_interfaces[0].subnet_id
    subnet_response = client.describe_subnets(subnet_ids: [subnet_id])
    az_id = subnet_response.subnets[0].availability_zone_id

    AwsInstance.create(instance_id: instance_id, az_id: az_id) { it.id = vm.id }

    hop_wait_instance_created
  end

  label def wait_instance_created
    instance_response = client.describe_instances({filters: [{name: "instance-id", values: [vm.aws_instance.instance_id]}, {name: "tag:Ubicloud", values: ["true"]}]}).reservations[0].instances[0]
    if instance_response.dig(:state, :name) == "running"
      public_ipv4 = instance_response.dig(:network_interfaces, 0, :association, :public_ip)
      AssignedVmAddress.create_with_id(
        dst_vm_id: vm.id,
        ip: public_ipv4
      )
      vm.sshable&.update(host: public_ipv4)
      vm.update(cores: vm.vcpus / 2, allocated_at: Time.now, ephemeral_net6: instance_response.dig(:network_interfaces, 0, :ipv_6_addresses, 0, :ipv_6_address))

      pop "vm created"
    end
    nap 1
  end

  label def destroy
    if vm.aws_instance
      begin
        client.terminate_instances(instance_ids: [vm.aws_instance.instance_id])
      rescue Aws::EC2::Errors::InvalidInstanceIDNotFound
      end

      vm.aws_instance.destroy
    end

    pop "vm destroyed"
  end

  def client
    @client ||= vm.location.location_credential.client
  end
end
