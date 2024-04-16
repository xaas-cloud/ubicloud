#!/bin/env ruby
# frozen_string_literal: true

require "json"

secrets = JSON.parse($stdin.read)

unless (storage_secrets = secrets["storage"])
  puts "need storage secrets in secrets json"
  exit 1
end

unless (params_path = ARGV.shift)
  puts "expected path to prep.json as argument"
  exit 1
end

params_json = File.read(params_path)
params = JSON.parse(params_json)

require "fileutils"
require_relative "../../common/lib/util"
require_relative "../lib/vm_setup"

VmSetup.new(params).prep(storage_secrets)
