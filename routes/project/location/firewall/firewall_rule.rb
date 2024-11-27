# frozen_string_literal: true

class Clover
  hash_branch(:project_location_firewall_prefix, "firewall-rule") do |r|
    # This is api-only, but is only called from an r.on api? branch, so no check is needed here

    r.post true do
      authorize("Firewall:edit", @firewall.id)

      required_params = %w[cidr]
      optional_params = %w[port_range]
      validated_params = validate_request_params(required_params, optional_params)

      parsed_cidr = Validation.validate_cidr(validated_params["cidr"])
      port_range = if validated_params["port_range"].nil?
        [0, 65535]
      else
        validated_params["port_range"] = Validation.validate_port_range(validated_params["port_range"])
      end

      pg_range = Sequel.pg_range(port_range.first..port_range.last)

      firewall_rule = @firewall.insert_firewall_rule(parsed_cidr.to_s, pg_range)

      Serializers::FirewallRule.serialize(firewall_rule)
    end

    r.is String do |firewall_rule_ubid|
      firewall_rule = FirewallRule.from_ubid(firewall_rule_ubid)

      request.delete true do
        if firewall_rule
          authorize("Firewall:edit", @firewall.id)
          @firewall.remove_firewall_rule(firewall_rule)
        end

        response.status = 204
        r.halt
      end

      request.get true do
        if firewall_rule
          authorize("Firewall:view", @firewall.id)
          Serializers::FirewallRule.serialize(firewall_rule)
        end
      end
    end
  end
end
