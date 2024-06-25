# frozen_string_literal: true

Sequel.migration do
  change do
    create_enum(:lb_connection_state, %w[connected disconnected])
    create_enum(:lb_protocol, %w[tcp udp])

    create_table(:load_balancer) do
      column :id, :uuid, primary_key: true
      column :name, :text, null: false
      column :protocol, :lb_protocol, null: false, default: "tcp"
      column :src_port, :integer, null: false
      column :dst_port, :integer, null: false
      column :health_check_endpoint, :text
      column :health_check_interval, :intege
      column :health_check_timeout, :integer
      column :health_check_retries, :integer
      foreign_key :private_subnet_id, :private_subnet, type: :uuid, null: false
      column :kid, :text, collate: "C"
    end

    create_table(:load_balancers_vms) do
      foreign_key :load_balancer_id, :load_balancer, type: :uuid, null: false
      foreign_key :vm_id, :vm, type: :uuid, null: false
      column :state, :lb_connection_state, null: false, default: "connected"
      primary_key [:load_balancer_id, :vm_id]
    end
  end
end
