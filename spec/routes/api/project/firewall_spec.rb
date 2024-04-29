# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Clover, "firewall" do
  let(:user) { create_account }

  let(:project) { user.create_project_with_default_policy("project-1") }

  let(:firewall) { Firewall.create_with_id(name: "default-firewall").associate_with_project(project) }

  describe "unauthenticated" do
    it "not list" do
      get "/api/project/#{project.ubid}/firewall"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not create" do
      post "/api/project/#{project.ubid}/firewall"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not delete" do
      delete "/api/project/#{project.ubid}/firewall/#{firewall.ubid}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not get" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not associate" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/attach-to-subnet"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end

    it "not dissociate" do
      get "/api/project/#{project.ubid}/firewall/#{firewall.ubid}/detach-from-subnet"

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)["error"]["message"]).to eq("Please login to continue")
    end
  end

  describe "authenticated" do
    before do
      login_api(user.email)
    end

    it "success all firewalls" do
      Firewall.create_with_id(name: firewall.name).associate_with_project(project)

      get "/api/project/#{project.ubid}/firewall"

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["items"].length).to eq(2)
    end

    it "success create firewall" do
      post "/api/project/#{project.ubid}/firewall", {
        name: "default-firewall-2",
        description: "default-firewall-description"
      }

      puts last_response.inspect

      expect(last_response.status).to eq(200)
    end
  end
end
