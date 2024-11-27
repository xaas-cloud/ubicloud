# frozen_string_literal: true

class Clover
  def postgres_post(name)
    authorize("Postgres:create", @project.id)
    fail Validation::ValidationFailed.new({billing_info: "Project doesn't have valid billing information"}) unless @project.has_valid_payment_method?

    Validation.validate_postgres_location(@location)

    required_params = %w[size]
    required_params << "name" << "location" if web?
    optional_params = %w[storage_size ha_type version flavor]
    validated_params = validate_request_params(required_params, optional_params)
    parsed_size = Validation.validate_postgres_size(@location, validated_params["size"])

    ha_type = validated_params["ha_type"] || PostgresResource::HaType::NONE
    requested_standby_count = case ha_type
    when PostgresResource::HaType::ASYNC then 1
    when PostgresResource::HaType::SYNC then 2
    else 0
    end

    requested_postgres_core_count = (requested_standby_count + 1) * parsed_size.vcpu / 2
    Validation.validate_core_quota(@project, "PostgresCores", requested_postgres_core_count)

    st = Prog::Postgres::PostgresResourceNexus.assemble(
      project_id: @project.id,
      location: @location,
      name:,
      target_vm_size: parsed_size.vm_size,
      target_storage_size_gib: validated_params["storage_size"] || parsed_size.storage_size_options.first,
      ha_type: validated_params["ha_type"] || PostgresResource::HaType::NONE,
      version: validated_params["version"] || PostgresResource::DEFAULT_VERSION,
      flavor: validated_params["flavor"] || PostgresResource::Flavor::STANDARD
    )
    send_notification_mail_to_partners(st.subject, current_account.email)

    if api?
      Serializers::Postgres.serialize(st.subject, {detailed: true})
    else
      flash["notice"] = "'#{name}' will be ready in a few minutes"
      request.redirect "#{@project.path}#{PostgresResource[st.id].path}"
    end
  end

  def postgres_list
    dataset = dataset_authorize(@project.postgres_resources_dataset, "Postgres:view").eager(:semaphores, :strand)
    if api?
      dataset = dataset.where(location: @location) if @location
      result = dataset.paginated_result(
        start_after: request.params["start_after"],
        page_size: request.params["page_size"],
        order_column: request.params["order_column"]
      )

      {
        items: Serializers::Postgres.serialize(result[:records]),
        count: result[:count]
      }
    else
      dataset = dataset.eager(:representative_server, :timeline)
      @postgres_databases = Serializers::Postgres.serialize(dataset.all, {include_path: true})
      view "postgres/index"
    end
  end

  def send_notification_mail_to_partners(resource, user_email)
    if [PostgresResource::Flavor::PARADEDB, PostgresResource::Flavor::LANTERN].include?(resource.flavor) && (email = Config.send(:"postgres_#{resource.flavor}_notification_email"))
      flavor_name = resource.flavor.capitalize
      Util.send_email(email, "New #{flavor_name} Postgres database has been created.",
        greeting: "Hello #{flavor_name} team,",
        body: ["New #{flavor_name} Postgres database has been created.",
          "ID: #{resource.ubid}",
          "Location: #{resource.location}",
          "Name: #{resource.name}",
          "E-mail: #{user_email}",
          "Instance VM Size: #{resource.target_vm_size}",
          "Instance Storage Size: #{resource.target_storage_size_gib}",
          "HA: #{resource.ha_type}"])
    end
  end
end
