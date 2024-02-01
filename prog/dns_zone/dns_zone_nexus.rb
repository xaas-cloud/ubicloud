# frozen_string_literal: true

require_relative "../../lib/util"

class Prog::DnsZone::DnsZoneNexus < Prog::Base
  subject_is :dns_zone

  semaphore :refresh_dns_servers

  def self.assemble(project_id:, name:, vm_count:, location:, vm_size:, storage_size_gib:)
    unless Project[project_id]
      fail "No existing project"
    end

    DB.transaction do
      dns_zone = DnsZone.create_with_id(project_id: project_id, name: name)

      vm_count.times do |i|
        ds_strand = Prog::DnsZone::DnsServerNexus.assemble(dns_zone.id)
        dns_zone.add_dns_server(ds_strand.dns_server)
      end

      Strand.create(prog: "DnsZone::DnsZoneNexus", label: "wait_servers") { _1.id = dns_zone.id }
    end
  end

  def before_run
    when_refresh_dns_servers_set? do
      hop_refresh_dns_servers
    end
  end

  label def wait_servers
    nap 5 unless dns_zone.dns_servers.map(&:strand).all? { _1.label == "wait" }
  end

  label def wait
    if dns_zone.last_purged_at < Time.now - 60 * 60 * 1 # ~1 hour
      register_deadline(:wait, 5 * 60)
      hop_purge_dns_records
    end

    when_refresh_dns_servers_set? do
      register_deadline(:wait, 5 * 60)
      hop_refresh_dns_servers
    end

    nap 10
  end

  label def refresh_dns_servers
    decr_refresh_dns_servers

    dns_zone.dns_servers.each do |dns_server|
      records_to_rectify = dns_zone.records_dataset
        .left_join(:seen_dns_records_by_dns_servers, dns_record_id: :id, dns_server_id: dns_server.id)
        .where(Sequel[:seen_dns_records_by_dns_servers][:dns_record_id] => nil)
        .order(Sequel.asc(:created_at)).all

      next if records_to_rectify.empty?

      commands = ["zone-abort #{dns_zone.name}", "zone-begin #{dns_zone.name}"]
      records_to_rectify.each do |r|
        commands << if r.tombstoned
          "zone-unset #{dns_zone.name} #{r.name} #{r.ttl} #{r.type} #{r.data}"
        else
          "zone-set #{dns_zone.name} #{r.name} #{r.ttl} #{r.type} #{r.data}"
        end
      end
      commands << "zone-commit #{dns_zone.name}"

      dns_server.run_commands_on_all_vms(commands)

      DB[:seen_dns_records_by_dns_servers].multi_insert(records_to_rectify.map { {dns_record_id: _1.id, dns_server_id: dns_server.id} })
    end

    hop_wait
  end

  label def purge_dns_records
    # These are the records that are obsoleted by a another record with the
    # same fields but newer date. We can delete them even if they are not
    # seen yet.
    obsoleted_records = dns_zone.records_dataset
      .join(
        dns_zone.records_dataset
          .select_group(:dns_zone_id, :name, :type, :data)
          .select_append { max(created_at).as(:latest_created_at) }
          .as(:latest_dns_record),
        [:dns_zone_id, :name, :type, :data]
      )
      .where { dns_record[:created_at] < latest_dns_record[:latest_created_at] }.all

    # These are the tombstoned records, we can only delete them if they are
    # seen by all DNS servers. We join with seen_dns_records_by_dns_servers
    # and count the number of DNS servers to ensure that they are seen by all
    # DNS servers.
    dns_server_ids = dns_zone.dns_servers.map(&:id)
    seen_tombstoned_records = dns_zone.records_dataset
      .select_group(:id)
      .join(:seen_dns_records_by_dns_servers, dns_record_id: :id, dns_server_id: dns_server_ids)
      .where(tombstoned: true)
      .having { count.function.* =~ dns_server_ids.count }.all

    records_to_purge = obsoleted_records + seen_tombstoned_records
    DB[:seen_dns_records_by_dns_servers].where(dns_record_id: records_to_purge.map(&:id).uniq).delete(force: true)
    records_to_purge.uniq(&:id).map(&:destroy)

    dns_zone.last_purged_at = Time.now
    dns_zone.save_changes

    hop_wait
  end
end
