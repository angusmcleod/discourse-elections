require "rails_helper"

describe ::DiscourseElections::ElectionController do
  routes { ::DiscourseElections::Engine.routes }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }

  describe "#create" do

    context "while logged in as an admin" do
      let!(:admin) { log_in(:admin) }

      it "works" do
        xhr :put, :create, category_id: category.id, position: "Moderator"
        expect(response).to be_success
        json = ::JSON.parse(response.body)
        expect(json['url']).to eq(Topic.last.relative_url)
      end

      it "requires category to be for elections" do
        category.custom_fields["for_elections"] = false
        category.save_custom_fields(true)
        expect { xhr :put, :create, category_id: category.id, position: "Moderator" }
          .to raise_error(StandardError, I18n.t("election.errors.category_not_enabled"))
      end

      it "requires a position" do
        expect { xhr :put, :create, category_id: category.id }.to raise_error(ActionController::ParameterMissing)
      end

      it "requires a category" do
        expect { xhr :put, :create, position: "Moderator" }.to raise_error(ActionController::ParameterMissing)
      end
    end

    it "requires the user to be an elections admin" do
      xhr :put, :create, category_id: category.id, position: "Moderator"
      expect(response).not_to be_success
      json = ::JSON.parse(response.body)
      expect(json["errors"][0]).to eq(I18n.t("invalid_access"))
    end
  end

  context "within election topic" do
    let (:topic) { Fabricate(:topic, subtype: 'election',
                                      category_id: category.id,
                                      title: I18n.t('election.title', position: 'Moderator'),
                                      user: Discourse.system_user,
                                      custom_fields: {
                                        position: 'Moderator',
                                        election_status: Topic.election_statuses[:nomination]
                                      })}
    let (:post) { Fabricate(:post, topic: topic,
                                   post_number: 1,
                                   raw: I18n.t('election.nomination.default_message'))}

    context "while logged in as an admin" do
      let!(:admin) { log_in(:admin) }

      describe "#start_poll" do

        context "while election has 2 or more nominations" do
          let(:user1) { Fabricate(:user) }
          let(:user2) { Fabricate(:user) }

          before do
            topic.custom_fields['election_nominations'] = [ user1.id, user2.id ]
            topic.save_custom_fields(true)
            post
          end

          it "works" do
            message = MessageBus.track_publish do
              xhr :put, :start_poll, topic_id: topic.id
            end.find { |m| m.channel.include?("polls") }

            expect(message.data[:post_id]).to eq(post.id)
          end
        end

        it "requires at least 2 nominees" do
          user1 = Fabricate(:user)
          topic.custom_fields['election_nominations'] = [ user1.id ]
          topic.save_custom_fields(true)
          post

          expect { xhr :put, :start_poll, topic_id: topic.id }.to raise_error(StandardError, I18n.t('election.errors.more_nominations'))
        end
      end
    end
  end


end
