#  frozen_string_literal: true

require_relative "../../model"

class KubernetesCluster < Sequel::Model
  one_to_one :strand, key: :id
  one_to_one :api_server_lb, class: :LoadBalancer, key: :id, primary_key: :api_server_lb_id_id
  one_to_one :private_subnet
  many_to_many :vms

  dataset_module Pagination

  include ResourceMethods
  include SemaphoreMethods
  include Authorization::HyperTagMethods

  def display_location
    LocationNameConverter.to_display_name(location)
  end

  def hyper_tag_name(project)
    "project/#{project.ubid}/location/#{display_location}/kubernetes-cluster/#{name}"
  end

  def path
    "/location/#{display_location}/kubernetes-cluster/#{name}"
  end
end
