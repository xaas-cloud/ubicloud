# frozen_string_literal: true

require_relative "../../lib/util"

class Prog::Test::Postgres < Prog::Test::Base
  semaphore :destroy

  def self.assemble(vm_host_id, test_cases)
    postgres_service_project = Project.create(name: "Postgres-Service-Project") { _1.id = Config.postgres_service_project_id }
    postgres_service_project.associate_with_project(postgres_service_project)

    postgres_test_project = Project.create_with_id(name: "Postgres-Test-Project")
    postgres_test_project.associate_with_project(postgres_test_project)

    Strand.create_with_id(
      prog: "Test::Postgres",
      label: "start",
      stack: [{
        "vm_host_id" => vm_host_id,
        "test_cases" => test_cases,
        "postgres_test_project_id" => postgres_test_project.id
      }]
    )

  end

  label def start
    hop_download_boot_images
  end

  label def download_boot_images
    frame["test_cases"].each do |test_case|
      puts "Downloading boot image for test case: #{test_case}"
      puts "Details: #{tests[test_case]}"
      flavor = "-#{tests[test_case]["postgres_flavor"]}"
      flavor = "" if flavor == "-standard"
      image_name = "postgres#{tests[test_case]["postgres_version"]}#{flavor}-ubuntu-2204"
      bud Prog::DownloadBootImage, {"subject_id" => frame["vm_host_id"], "image_name" => image_name}
    end

    hop_wait_download_boot_images
  end

  label def wait_download_boot_images
    reap
    hop_create_postgres_resources if leaf?
    donate
  end

  label def create_postgres_resources
    strands = frame["test_cases"].map do |test_case|
      st = Prog::Postgres::PostgresResourceNexus.assemble(
        project_id: frame["postgres_test_project_id"],
        location: "hetzner-fsn1",
        name: "postgres-test-#{tests[test_case]["postgres_version"]}-#{tests[test_case]["postgres_flavor"]}",
        target_vm_size: "standard-2",
        target_storage_size_gib: 128,
        version: tests[test_case]["postgres_version"],
        flavor: tests[test_case]["postgres_flavor"],
        ha_type: tests[test_case]["ha_type"]
      )
      bud Prog::Postgres::PostgresResourceNexus, {"subject_id" => st.id}
      st
    end

    # Store resource IDs for later use
    update_stack({"postgres_resource_ids" => strands.map(&:id)})
    hop_wait_postgres_resources
  end

  label def wait_postgres_resources
    resources_ready = frame["postgres_resource_ids"].all? do |id|
      postgres_resource = PostgresResource[id]
      # Resource is ready when in "wait" state and can run a query
      postgres_resource.strand.label == "wait" &&
        postgres_resource.representative_server.run_query("SELECT 1") == "1"
    end

    if resources_ready
      hop_test_postgres_resources
    else
      nap 10
    end
  end

  label def test_postgres_resources
    frame["postgres_resource_ids"].each do |id|
      bud Prog::Test::PostgresResource, {"subject_id" => id}
    end
    hop_wait_tests
  end

  label def wait_tests
    reap
    if leaf?
      hop_destroy
    else
      nap 10
    end
  end

  label def destroy
    frame["postgres_resource_ids"].each do |id|
      postgres_resource = PostgresResource[id]
      postgres_resource.incr_destroy if postgres_resource
    end

    frame["fail_message"] ? fail_test(frame["fail_message"]) : hop_finish
  end

  label def finish
    pop "PostgresResource tests are finished!"
  end

  label def failed
    nap 15
  end

  def tests
    @tests ||= YAML.load_file("config/postgres_e2e_tests.yml").to_h { [_1["name"], _1] }
  end
end
