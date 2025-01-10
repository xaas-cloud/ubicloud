# frozen_string_literal: true

require_relative "../../lib/util"

class Prog::Test::PosgresResource < Prog::Test::Base
  semaphore :destroy
  subject_is :postgres_resource

  def self.assemble(postgres_resource_id)
    Strand.create_with_id(
      prog: "Test::PostgresResource",
      label: "start",
      stack: [{
        "subject_id" => postgres_resource_id
      }]
    )
  end

  label def start
    hop_test_basic_connectivity
  end

  label def test_basic_connectivity
    # Test basic connectivity and version
    server = postgres_resource.representative_server

    begin
      # Basic connectivity test
      result = server.run_query("SELECT 1")
      fail_test("[#{postgres_resource.name}] Basic connectivity test failed") unless result == "1"

      # Version test
      version = server.run_query("SHOW server_version")
      fail_test("[#{postgres_resource.name}] Version mismatch") unless version.start_with?(postgres_resource.version)

      hop_finish
    rescue => e
      fail_test("[#{postgres_resource.name}] Connectivity test failed: #{e.message}")
    end
  end

  label def finish
    pop "PostgresResource tests are finished!"
  end

  label def failed
    nap 15
  end
end
