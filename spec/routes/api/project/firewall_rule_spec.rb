# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Clover, "firewall" do
  let(:user) { create_account }

  let(:project) { user.create_project_with_default_policy("project-1") }

  let(:firewall) { Firewall.create_with_id(name: "default-firewall").tap { _1.associate_with_project(project) } }

  let(:firewall_rule) { FirewallRule.create_with_id(firewall_id: firewall.id, cidr: "0.0.0.0/0", port_range: Sequel.pg_range(80..5432)) }

  describe "unauthenticated" do
    it "not list" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/firewall-rule"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not get" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/firewall-rule/#{firewall_rule.ubid}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not post" do
      post "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/firewall-rule"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not delete" do
      delete "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/firewall-rule/#{firewall_rule.ubid}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end
  end

  describe "authenticated" do
    before do
      login_api(user.email)
    end

    it "success get all firewall rules" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/firewall-rule"

      expect(last_response.status).to eq(200)
    end
  end
end
