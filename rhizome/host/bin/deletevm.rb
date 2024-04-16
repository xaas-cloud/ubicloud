#!/bin/env ruby
# frozen_string_literal: true

unless (vm_name = ARGV.shift)
  puts "need vm name as argument"
  exit 1
end

require_relative "../../common/lib/util"
require_relative "../lib/vm_setup"
require "json"

params_json = File.read(VmPath.new(vm_name).prep_json)
params = JSON.parse(params_json)
VmSetup.new(params).purge
