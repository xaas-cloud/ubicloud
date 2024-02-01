# frozen_string_literal: true

require "forwardable"

require_relative "../../lib/util"

class Prog::DnsZone::DnsZoneNexus < Prog::Base
  subject_is :minio_server

  extend Forwardable
  def_delegators :minio_server, :vm

  semaphore :checkup, :destroy, :restart, :reconfigure

  def self.assemble(name:, dns_zone_id:, location:, vm_size:, storage_size_gib:)
    unless (dns_zone = DnsZone[dns_zone_id])
      fail "No existing DNS zone"
    end

    DB.transaction do
      ubid = DnsServer.generate_ubid
      vm_st = Prog::Vm::Nexus.assemble_with_sshable(
        "ubi",
        dns_zone.project_id,
        location: location,
        name: ubid.to_s,
        size: vm_size,
        storage_volumes: [{encrypted: true, size_gib: storage_size_gib}],
        boot_image: "ubuntu-jammy",
        enable_ip4: true
      )

      dns_server = DnsServer.create(name: name) { _1.id = ubid.to_uuid }
      dns_server.add_vm(vm_st.subject)

      Strand.create(prog: "DnsZone::DnsZoneNexus", label: "wait_vm") { _1.id = dns_server.id }
    end
  end

  def before_run
    when_destroy_set? do
      if strand.label != "destroy"
        hop_destroy
      end
    end
  end

  label def wait_vm
    nap 5 unless dns_server.vms.map(&:strand).all? { _1.label == "wait" }
    register_deadline(:wait, 10 * 60)

    hop_wait_bootstrap_rhizome
  end
end
