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

    describe "#start_poll" do

      context "while logged in as an admin" do
        let!(:admin) { log_in(:admin) }

        context "while election has 2 or more nominations" do
          let(:user1) { Fabricate(:user) }
          let(:user2) { Fabricate(:user) }

          before do
            topic.custom_fields['election_nominations'] = [ user1.id, user2.id ]
            topic.save_custom_fields(true)
            post
          end

          it "works" do
            messages = MessageBus.track_publish do
              xhr :put, :start_poll, topic_id: topic.id
            end

            poll_message = messages.find { |m| m.channel.include?("polls") }
            expect(poll_message.data[:post_id]).to eq(post.id)

            expect( Topic.find(topic.id).election_status ).to eq(Topic.election_statuses[:poll])
          end
        end

        it "requires at least 2 nominees" do
          expect { xhr :put, :start_poll, topic_id: topic.id }.to raise_error(StandardError, I18n.t('election.errors.more_nominations'))
        end
      end

      it "requires the user to be an elections admin" do
        xhr :put, :start_poll, topic_id: topic.id
        expect(response).not_to be_success
        json = ::JSON.parse(response.body)
        expect(json["errors"][0]).to eq(I18n.t("invalid_access"))
      end
    end

    describe "#set_status" do

      context "while logged in as an admin" do
        let!(:admin) { log_in(:admin) }

        context "while election has 2 or more nominations" do
          let(:user1) { Fabricate(:user) }
          let(:user2) { Fabricate(:user) }

          before do
            topic.custom_fields['election_nominations'] = [ user1.id, user2.id ]
            topic.save_custom_fields(true)
            post
          end

          it "updates from nomination to poll" do
            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:poll]
            end.find { |m| m.channel.include?("polls") }

            poll = message.data[:polls]["poll"]

            expect(message.data[:post_id]).to eq(post.id)
            expect(poll["options"].length).to eq(2)
            expect(poll["options"][0]["html"]).to include(user1.username)
            expect(poll["options"][1]["html"]).to include(user2.username)

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:poll])
          end

          it "updates from nomination to closed poll" do
            DiscourseElections::ElectionTopic.set_status(topic.id, Topic.election_statuses[:poll])

            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:closed_poll]
            end.find { |m| m.channel.include?("polls") }

            expect(message.data[:post_id]).to eq(post.id)
            expect(message.data[:polls]["poll"]["status"]).to eq("closed")

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:closed_poll])
          end

          it "updates from poll to nomination" do
            DiscourseElections::ElectionTopic.set_status(topic.id, Topic.election_statuses[:poll])

            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:nomination]
            end.find { |m| m.channel == "/topic/#{topic.id}" }

            post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])

            expect(post.raw).to include(I18n.t('election.post.nominated'))
            expect(post.raw).to include(user1.username)
            expect(post.raw).to include(user2.username)

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:nomination])
          end

          it "updates from poll to closed poll" do
            DiscourseElections::ElectionTopic.set_status(topic.id, Topic.election_statuses[:poll])

            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:closed_poll]
            end.find { |m| m.channel.include?("polls") }

            expect(message.data[:post_id]).to eq(post.id)
            expect(message.data[:polls]["poll"]["status"]).to eq("closed")

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:closed_poll])
          end

          it "updates from closed poll to poll" do
            topic.custom_fields['election_statuses'] = Topic.election_statuses[:closed_poll]
            topic.save_custom_fields(true)

            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:poll]
            end.find { |m| m.channel.include?("polls") }

            expect(message.data[:post_id]).to eq(post.id)
            expect(message.data[:polls]["poll"]["status"]).to eq("open")

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:poll])
          end

          it "updates from closed poll to nomination" do
            DiscourseElections::ElectionTopic.set_status(topic.id, Topic.election_statuses[:closed_poll])

            message = MessageBus.track_publish do
              xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:nomination]
            end.find { |m| m.channel == "/topic/#{topic.id}" }

            post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])

            expect(post.raw).to include(I18n.t('election.post.nominated'))
            expect(post.raw).to include(user1.username)
            expect(post.raw).to include(user2.username)

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:nomination])
          end
        end

        it "requires at least 2 nominees to select a poll status" do
          expect { xhr :put, :set_status, topic_id: topic.id, status: Topic.election_statuses[:poll] }
            .to raise_error(StandardError, I18n.t('election.errors.more_nominations'))
        end
      end

      it "requires the user to be an elections admin" do
        xhr :put, :set_status, topic_id: topic.id
        expect(response).not_to be_success
        json = ::JSON.parse(response.body)
        expect(json["errors"][0]).to eq(I18n.t("invalid_access"))
      end
    end
  end


end
