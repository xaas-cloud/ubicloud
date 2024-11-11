# frozen_string_literal: true

require_relative "../model"

class Project < Sequel::Model
  one_to_many :access_tags
  one_to_many :access_policies
  one_to_one :billing_info, key: :id, primary_key: :billing_info_id
  one_to_many :usage_alerts
  one_to_many :github_installations

  many_to_many :accounts, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :vms, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :minio_clusters, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :private_subnets, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :postgres_resources, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :firewalls, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :load_balancers, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id
  many_to_many :inference_endpoints, join_table: :access_tag, left_key: :project_id, right_key: :hyper_tag_id

  one_to_many :invoices, order: Sequel.desc(:created_at)
  one_to_many :quotas, class: :ProjectQuota, key: :project_id
  one_to_many :invitations, class: :ProjectInvitation, key: :project_id
  one_to_many :api_keys, key: :owner_id, class: :ApiKey, conditions: {owner_table: "project"}

  dataset_module Authorization::Dataset
  dataset_module Pagination

  plugin :association_dependencies, access_tags: :destroy, access_policies: :destroy, billing_info: :destroy, github_installations: :destroy, api_keys: :destroy

  include ResourceMethods
  include Authorization::HyperTagMethods

  def hyper_tag_name(project = nil)
    "project/#{ubid}"
  end

  include Authorization::TaggableMethods

  def has_valid_payment_method?
    return true unless Config.stripe_secret_key
    !!billing_info&.payment_methods&.any?
  end

  def default_location
    location_max_capacity = DB[:vm_host]
      .where(location: Option.locations.map { _1.name })
      .where(allocation_state: "accepting")
      .select_group(:location)
      .order { sum(Sequel[:total_cores] - Sequel[:used_cores]).desc }
      .first

    if location_max_capacity.nil?
      Option.locations.first.name
    else
      location_max_capacity[:location]
    end
  end

  def path
    "/project/#{ubid}"
  end

  def has_resources
    access_tags_dataset.exclude(hyper_tag_table: [Account.table_name.to_s, Project.table_name.to_s, AccessTag.table_name.to_s]).count > 0 || github_installations.flat_map(&:runners).count > 0
  end

  def soft_delete
    DB.transaction do
      access_tags_dataset.destroy
      access_policies_dataset.destroy
      github_installations.each { Prog::Github::DestroyGithubInstallation.assemble(_1) }

      # We still keep the project object for billing purposes.
      # These need to be cleaned up manually once in a while.
      # Don't forget to clean up billing info and payment methods.
      update(visible: false)
    end
  end

  def current_invoice
    begin_time = invoices.first&.end_time || Time.new(Time.now.year, Time.now.month, 1)
    end_time = Time.now

    if (invoice = InvoiceGenerator.new(begin_time, end_time, project_ids: [id]).run.first)
      return invoice
    end

    content = {
      "resources" => [],
      "subtotal" => 0.0,
      "credit" => 0.0,
      "discount" => 0.0,
      "cost" => 0.0
    }

    Invoice.new(project_id: id, content: content, begin_time: begin_time, end_time: end_time, created_at: Time.now, status: "current")
  end

  def current_resource_usage(resource_type)
    case resource_type
    when "VmCores" then vms.sum(&:cores)
    when "GithubRunnerCores" then github_installations.sum(&:total_active_runner_cores)
    when "PostgresCores" then postgres_resources.flat_map { _1.servers.map { |s| s.vm.cores } }.sum
    else
      raise "Unknown resource type: #{resource_type}"
    end
  end

  def effective_quota_value(resource_type)
    default_quota = ProjectQuota.default_quotas[resource_type]
    override_quota_value = quotas_dataset.first(quota_id: default_quota["id"])&.value
    override_quota_value || default_quota["#{reputation}_value"]
  end

  def quota_available?(resource_type, requested_additional_usage)
    effective_quota_value(resource_type) >= current_resource_usage(resource_type) + requested_additional_usage
  end

  def create_api_key(used_for: "inference_endpoint")
    ApiKey.create_with_id(owner_table: Project.table_name, owner_id: id, used_for: used_for)
  end

  def generate_postgres_options(flavor: "standard")
    options = OptionTreeGenerator.new

    options.add_option(name: "name")
    options.add_option(name: "flavor", values: flavor)
    options.add_option(name: "location", values: Option.postgres_locations.map(&:display_name), parent: "flavor")
    options.add_option(name: "size", values: [2, 4, 8, 16, 30, 60].map { "standard-#{_1}" }, parent: "location")

    options.add_option(name: "storage_size", values: ["128", "256", "512", "1024", "2048", "4096"], parent: "size") do |flavor, location, size, storage_size|
      size = size.split("-").last.to_i
      lower_limit = [size * 64, 1024].min
      upper_coefficient = (location == "hetzner-fsn1") ? 256 : 128
      storage_size.to_i >= lower_limit && storage_size.to_i <= size * upper_coefficient
    end

    options.add_option(name: "version", values: ["16", "17"], parent: "flavor") do |flavor, version|
      flavor != PostgresResource::Flavor::LANTERN || version == "16"
    end

    options.add_option(name: "ha_type", values: ["none", "async", "sync"], parent: "storage_size")
    options.serialize
  end

  def generate_firewall_options(account:)
    options = OptionTreeGenerator.new
    options.add_option(name: "name")
    options.add_option(name: "description")
    options.add_option(name: "location", values: Option.locations.map(&:display_name))
    subnets = private_subnets_dataset.authorized(account.id, "PrivateSubnet:view").map {
      {
        location: LocationNameConverter.to_display_name(_1.location),
        value: _1.ubid,
        display_name: _1.name
      }
    }
    options.add_option(name: "private_subnet_id", values: subnets, parent: "location") do |location, private_subnet|
      private_subnet[:location] == location
    end
    options.serialize
  end

  def generate_load_balancer_options(account:)
    options = OptionTreeGenerator.new
    options.add_option(name: "name")
    options.add_option(name: "description")
    options.add_option(name: "private_subnet_id", values: private_subnets_dataset.authorized(account.id, "PrivateSubnet:view").map { {value: _1.ubid, display_name: _1.name} })
    options.add_option(name: "algorithm", values: ["Round Robin", "Hash Based"].map { {value: _1.downcase.tr(" ", "_"), display_name: _1} })
    options.add_option(name: "src_port")
    options.add_option(name: "dst_port")
    options.add_option(name: "health_check_endpoint")
    options.add_option(name: "health_check_protocol", values: ["http", "https", "tcp"].map { {value: _1, display_name: _1.upcase} })
    options.serialize
  end

  def self.feature_flag(*flags, into: self)
    flags.map(&:to_s).each do |flag|
      into.module_eval do
        define_method :"set_ff_#{flag}" do |value|
          update(feature_flags: feature_flags.merge({flag => value}))
        end

        define_method :"get_ff_#{flag}" do
          feature_flags[flag]
        end
      end
    end
  end

  feature_flag :postgresql_base_image, :vm_public_ssh_keys, :transparent_cache, :location_latitude_fra
end
