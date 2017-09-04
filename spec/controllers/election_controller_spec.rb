require "rails_helper"

shared_examples 'requires election admin' do |method, action, params|
  it 'raises an exception when election admin not present' do
    xhr method, action, params
    expect(response).not_to be_success
    json = ::JSON.parse(response.body)
    expect(json["errors"][0]).to eq(I18n.t("invalid_access"))
  end
end

describe ::DiscourseElections::ElectionController do
  routes { ::DiscourseElections::Engine.routes }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }

  describe "#create" do
    include_examples 'requires election admin', :put, :create, category_id: 3, position: "Moderator"

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
      include_examples 'requires election admin', :put, :start_poll, topic_id: 5

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
    end

    describe "#set_status" do
      include_examples 'requires election admin', :put, :set_status, topic_id: 6

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
    end

    describe "set_self_nomination" do
      include_examples 'requires election admin', :put, :set_self_nomination, topic_id: 7

      context "while logged in as an admin" do
        let!(:admin) { log_in(:admin) }

        it "works" do
          xhr :put, :set_self_nomination, topic_id: topic.id, state: true
          expect(response).to be_success
          json = ::JSON.parse(response.body)
          expect(json['state']).to eq(true)
        end

        it "should prevent an update if the state has not changed" do
          topic.custom_fields['election_self_nomination_allowed'] = false
          topic.save_custom_fields(true)

          expect { xhr :put, :set_self_nomination, topic_id: topic.id, state: false }
            .to raise_error(StandardError, I18n.t('election.errors.self_nomination_state_not_changed'))
        end
      end
    end

    describe "set_message" do
      include_examples 'requires election admin', :put, :set_message, topic_id: 8, message: "Test message"

      context "while logged in as an admin" do
        let!(:admin) { log_in(:admin) }

        it "updates stored message" do
          message = "Example message: Oranges"
          xhr :put, :set_message, topic_id: topic.id, message: message, type: 'nomination'

          updated_topic = Topic.find(topic.id)
          expect(updated_topic.custom_fields["election_nomination_message"]).to eq(message)
        end

        it "updates nomination message in election post" do
          nomination_message = "Example message: Bananas"
          post

          message = MessageBus.track_publish do
            xhr :put, :set_message, topic_id: topic.id, message: nomination_message, type: 'nomination'
          end.find { |m| m.channel == "/topic/#{topic.id}" }

          post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
          expect(post.raw).to include(nomination_message)
        end

        it "updates poll message in election post" do
          poll_message = "Example message: Apples"
          post

          topic.custom_fields['election_status'] = Topic.election_statuses[:poll]
          topic.custom_fields['election_nominations'] = [ Fabricate(:user).id, Fabricate(:user).id ]
          topic.save_custom_fields(true)

          message = MessageBus.track_publish do
            xhr :put, :set_message, topic_id: topic.id, message: poll_message, type: 'poll'
          end.find { |m| m.channel == "/topic/#{topic.id}" }

          post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
          expect(post.raw).to include(poll_message)
        end
      end
    end
  end
end
