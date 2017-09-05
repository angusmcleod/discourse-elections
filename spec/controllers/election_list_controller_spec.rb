require "rails_helper"

describe ::DiscourseElections::ElectionListController do
  routes { ::DiscourseElections::Engine.routes }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }

  let(:topic) { Fabricate(:topic, subtype: 'election',
                                  category_id: category.id,
                                  title: I18n.t('election.title', position: 'Moderator'),
                                  user: Discourse.system_user,
                                  custom_fields: {
                                    election_position: 'Moderator',
                                    election_status: Topic.election_statuses[:nomination]
                                  }) }

  describe "category_list" do
    it "works" do
      topic
      xhr :get, :category_list, category_id: category.id
      json = ::JSON.parse(response.body)
      expect(json[0]['position']).to eq('Moderator')
      expect(json[0]['relative_url']).to include('moderator')
      expect(json[0]['status']).to eq(Topic.election_statuses[:nomination])
    end
  end
end
