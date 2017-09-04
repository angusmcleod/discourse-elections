require "rails_helper"

describe ::DiscourseElections::ElectionController do
  routes { ::DiscourseElections::Engine.routes }

  describe "#create" do
    let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }

    it "works" do
      log_in_user(Fabricate(:admin))

      xhr :put, :create, category_id: category.id, position: "Moderator"

      expect(response).to be_success
      json = ::JSON.parse(response.body)
      expect(json['url']).to eq(Topic.last.relative_url)
    end

    it "requires category to be for elections" do
      category.custom_fields["for_elections"] = false
      category.save_custom_fields(true)

      log_in(:admin)
      expect { xhr :put, :create, category_id: category.id, position: "Moderator" }
        .to raise_error(StandardError, I18n.t("election.errors.category_not_enabled"))
    end

    it "requires a position" do
      log_in(:admin)
      expect { xhr :put, :create, category_id: category.id }.to raise_error(ActionController::ParameterMissing)
    end

    it "requires a category" do
      log_in(:admin)
      expect { xhr :put, :create, position: "Moderator" }.to raise_error(ActionController::ParameterMissing)
    end

    it "requires the user to be an elections admin" do
      xhr :put, :create, position: "Moderator", category_id: category.id
      expect(response).not_to be_success
      json = ::JSON.parse(response.body)
      expect(json["errors"][0]).to eq(I18n.t("invalid_access"))
    end
  end
end
