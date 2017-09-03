require "rails_helper"

describe ::DiscourseElections::ElectionController do
  routes { ::DiscourseElections::Engine.routes }

  let(:category) { Fabricate(:category) }

  describe "#create" do

    it "works" do
      category.custom_fields['for_elections'] = true
      category.save_custom_fields(true)
      log_in_user(Fabricate(:admin))

      xhr :put, :create, category_id: category.id, position: "Moderator",
          nomination_message: "The job of moderator is one of the utmost responsibility",
          poll_message: "Select the candidate you think will best serve the community responsibly",
          self_nomination: true

      expect(response).to be_success
      json = ::JSON.parse(response.body)
      expect(json['url']).to eq(Topic.last.relative_url)
    end

  end
end
