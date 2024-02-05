# frozen_string_literal: true

class CloverApi
  hash_branch(:project_prefix, "private-subnet") do |r|
    @serializer = Serializers::Api::PrivateSubnet

    # TODO: Validation
    r.get true do
      result = @project.private_subnets_dataset.authorized(@current_user.id, "PrivateSubnet:view").paginated_result(
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
