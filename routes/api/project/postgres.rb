# frozen_string_literal: true

class CloverApi
  hash_branch(:project_prefix, "postgres") do |r|
    @serializer = Serializers::Api::Postgres

    r.get true do
      result = @project.postgres_resources_dataset.authorized(@current_user.id, "Postgres:view").paginated_result(
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
  end
end
