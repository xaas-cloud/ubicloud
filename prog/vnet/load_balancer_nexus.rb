# frozen_string_literal: true

require "openssl"
require "acme-client"

class Prog::Vnet::LoadBalancerNexus < Prog::Base
  subject_is :load_balancer
  semaphore :destroy, :update_load_balancer, :dns_challenge

  def self.assemble(private_subnet_id, name: nil, protocol: "tcp", src_port: nil,
    dst_port: nil, health_check_endpoint: nil, health_check_interval: nil,
    health_check_timeout: nil, health_check_retries: nil)

    unless PrivateSubnet[private_subnet_id]
      fail "Given subnet doesn't exist with the id #{private_subnet_id}"
    end

    ubid = LoadBalancer.generate_ubid

    DB.transaction do
      LoadBalancer.create(private_subnet_id: private_subnet_id, name: name,
        protocol: protocol, src_port: src_port, dst_port: dst_port,
        health_check_endpoint: health_check_endpoint,
        health_check_interval: health_check_interval,
        health_check_timeout: health_check_timeout,
        health_check_retries: health_check_retries) { _1.id = ubid.to_uuid }

      Strand.create(prog: "Vnet::LoadBalancerNexus", label: "start", stack: [{"private_key" => OpenSSL::PKey::RSA.new(4096)}]) { _1.id = ubid.to_uuid }
    end
  end

  def before_run
    when_destroy_set? do
      hop_destroy if strand.label != "destroy"
    end
  end

  def acme_client
    @acme_client ||= Acme::Client.new(private_key: frame["private_key"], directory: 'https://acme-staging-v02.api.letsencrypt.org/directory')
  end

  label def start
    account = acme_client.new_account(contact: 'mailto:furkan@ubicloud.com', terms_of_service_agreed: true)
    kid = account.kid
    load_balancer.update(kid: kid)
    hop_start_dns_challenge
  end

  label def start_dns_challenge
    order = acme_client.new_order(identifiers: ['furkansahin.work'])
    authorization = order.authorizations.first
    dns_challenge = authorization.dns
    puts "Please add the following DNS record to your domain's DNS configuration:"
    puts "Record type: #{dns_challenge.record_type}"
    puts "Record name: #{dns_challenge.record_name}"
    puts "Record content: #{dns_challenge.record_content}"
    puts "HASH: #{authorization.to_h}"

    Prog::Vnet::LoadBalancerNexus.dns_zone&.insert_record(record_name: dns_challenge.record_name, type: dns_challenge.record_type, ttl: 10, data: dns_challenge.record_content, zone: Prog::Vnet::LoadBalancerNexus.dns_zone.name)

    current_frame = strand.stack.first
    current_frame["order"] = order
    current_frame["dns_challenge"] = dns_challenge
    strand.modified!(:stack)
    strand.save_changes

    hop_wait_for_dns_challenge
  end

  label def wait_for_dns_challenge
    when_dns_challenge_set? do
      hop_request_challenge
    end

    nap 5
  end

  label def request_challenge
    challenge = frame["dns_challenge"]
    challenge.request_validation
    # wait

    hop_finalize
  end

  label def finalize
    csr = Acme::Client::CertificateRequest.new(names: ['furkansahin.work'])
    order = frame["order"]
    order.finalize(csr: csr)
    # wait

    hop_wait_for_certificate
  end

  label def wait_for_certificate
    order = frame["order"]
    order.reload
    if order.status == "valid"
      certificate = order.certificate
      load_balancer.update(certificate: certificate)
      hop_wait
    end

    nap 5
  end

  label def wait
    when_update_load_balancer_set? do
      load_balancer.vms.map { _1.incr_update_load_balancer }
      decr_update_load_balancer
    end

    nap 5
  end

  label def destroy
    decr_destroy
    load_balancer.vms.map { _1.incr_update_load_balancer }
    DB[:load_balancers_vms].where(load_balancer_id: load_balancer.id).delete(force: true)
    load_balancer.destroy

    pop "load balancer deleted"
  end

  def self.dns_zone
    @@dns_zone ||= DnsZone[project_id: Config.load_balancer_service_project_id, name: Config.load_balancer_service_hostname]
  end
end
