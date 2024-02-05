# frozen_string_literal: true

class CloverApi
  hash_branch(:project_location_prefix, "postgres") do |r|
    @serializer = Serializers::Api::Postgres

    r.get true do
      result = @project.postgres_resources_dataset.where(location: @location).authorized(@current_user.id, "Postgres:view").paginated_result(
        r.params["cursor"],
        r.params["page-size"],
        r.params["order-column"]
      )

      {
        values: serialize(result[:records]),
        next_cursor: result[:next_cursor],
        count: result[:count]
      }
    end

    r.on String do |pg_name|
      r.post true do
        Authorization.authorize(@current_user.id, "Postgres:create", @project.id)
        fail Validation::ValidationFailed.new({billing_info: "Project doesn't have valid billing information"}) unless @project.has_valid_payment_method?

        request_body_params = JSON.parse(request.body.read)

        parsed_size = Validation.validate_postgres_size(request_body_params["size"])
        st = Prog::Postgres::PostgresResourceNexus.assemble(
          project_id: @project.id,
          location: request_body_params["location"],
          name: pg_name,
          target_vm_size: parsed_size.vm_size,
          target_storage_size_gib: parsed_size.storage_size_gib
        )

        serialize(st.subject)
        r.halt
      end

      pg = @project.postgres_resources_dataset.where(location: @location).where { {Sequel[:postgres_resource][:name] => pg_name} }.first

      r.delete true do
        if pg
          Authorization.authorize(@current_user.id, "Postgres:delete", pg.id)
          pg.incr_destroy
        end

        response.status = 204
        r.halt
      end

      unless pg
        response.status = 404
        r.halt
      end

      r.get true do
        Authorization.authorize(@current_user.id, "Postgres:view", pg.id)
        serialize(pg, :detailed)
      end

      r.post "restore" do
        Authorization.authorize(@current_user.id, "Postgres:create", @project.id)
        Authorization.authorize(@current_user.id, "Postgres:view", pg.id)

        request_body_params = JSON.parse(request.body.read)

        st = Prog::Postgres::PostgresResourceNexus.assemble(
          project_id: @project.id,
          location: pg.location,
          name: request_body_params["name"],
          target_vm_size: pg.target_vm_size,
          target_storage_size_gib: pg.target_storage_size_gib,
          parent_id: pg.id,
          restore_target: request_body_params["restore_target"]
        )

        serialize(st.subject, :detailed)
      end

      r.post "reset-superuser-password" do
        Authorization.authorize(@current_user.id, "Postgres:create", @project.id)
        Authorization.authorize(@current_user.id, "Postgres:view", pg.id)

        request_body_params = JSON.parse(request.body.read)

        unless pg.server.primary?
          fail ErrorCodes::PostgresPrimaryError.new("Superuser password cannot be updated during restore!")
        end

        Validation.validate_postgres_superuser_password(request_body_params["password"])

        pg.update(superuser_password: request_body_params["password"])
        pg.server.incr_update_superuser_password

        response.status = 200
        r.halt
      end
    end
  end
end
