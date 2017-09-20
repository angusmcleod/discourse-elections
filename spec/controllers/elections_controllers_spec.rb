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
    let (:user) { Fabricate(:user) }
    let (:topic) { Fabricate(:topic, subtype: 'election',
                                     category_id: category.id,
                                     title: I18n.t('election.title', position: 'Moderator'),
                                     user: user,
                                     custom_fields: {
                                       position: 'Moderator',
                                       election_status: Topic.election_statuses[:nomination]
                                     })}
    let (:post) { Fabricate(:post, topic: topic,
                                   post_number: 1,
                                   raw: I18n.t('election.nomination.default_message'),
                                   user: user) }

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

            expect(Topic.find(topic.id).election_status).to eq(Topic.election_statuses[:poll])
          end
        end

        it "requires at least 2 nominees" do
          expect { xhr :put, :start_poll, topic_id: topic.id }.to raise_error(StandardError, I18n.t('election.errors.more_nominations'))
        end
      end
    end

    describe "#set_status" do
      include_examples 'requires election admin', :put, :set_status, topic_id: 6, status: 2

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
      include_examples 'requires election admin', :put, :set_self_nomination, topic_id: 7, state: true

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

        it "dynamically updates nomination message in election post" do
          nomination_message = "Example message: Bananas"
          post

          message = MessageBus.track_publish do
            xhr :put, :set_message, topic_id: topic.id, message: nomination_message, type: 'nomination'
          end.find { |m| m.channel == "/topic/#{topic.id}" }

          post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
          expect(post.raw).to include(nomination_message)
        end

        it "dynamically updates poll message in election post" do
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

        it "works with an empty message" do
          xhr :put, :set_message, topic_id: topic.id, type: "nomination", message: ""
          expect(response).to be_success
        end

        it "requires a message" do
          expect { xhr :put, :set_message, topic_id: topic.id, type: "nomination" }.to raise_error(ActionController::ParameterMissing)
        end
      end
    end

    describe "set_position" do
      include_examples 'requires election admin', :put, :set_position, topic_id: 12, position: "Grand Poobah"

      context "while logged in as an admin" do
        let!(:admin) { log_in(:admin) }

        it "works" do
          position = "Wizard"
          xhr :put, :set_position, topic_id: topic.id, position: position
          expect(response).to be_success

          updated_topic = Topic.find(topic.id)
          expect(updated_topic.custom_fields["election_position"]).to eq(position)
          expect(updated_topic.title).to include(position)
        end

        it "requires a minimum length of 3" do
          expect { xhr :put, :set_position, topic_id: topic.id, position: "ha" }
            .to raise_error(StandardError, I18n.t('election.errors.position_too_short'))
        end
      end
    end
  end
end

describe ::DiscourseElections::ElectionListController do
  routes { ::DiscourseElections::Engine.routes }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }

  let(:topic) { Fabricate(:topic, subtype: 'election',
                                  category_id: category.id,
                                  title: I18n.t('election.title', position: 'Moderator'),
                                  user: Fabricate(:admin),
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

describe ::DiscourseElections::NominationController do
  routes { ::DiscourseElections::Engine.routes }

  let(:user1) { Fabricate(:user) }
  let(:user2) { Fabricate(:user) }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }
  let(:topic) { Fabricate(:topic, subtype: 'election',
                                  category_id: category.id,
                                  title: I18n.t('election.title', position: 'Moderator'),
                                  user: Fabricate(:admin),
                                  custom_fields: {
                                    election_position: 'Moderator',
                                    election_status: Topic.election_statuses[:nomination]
                                  }) }
  let(:election_post) { Fabricate(:post, topic: topic,
                                         post_number: 1,
                                         raw: I18n.t('election.nomination.default_message')) }
  let(:nomination_statement_post) { Fabricate(:post, topic: topic,
                                                     user_id: user1.id,
                                                     post_number: 2,
                                                     custom_fields: {
                                                       election_nomination_statement: true
                                                     }) }

  describe "set_by_username" do
    let!(:user) { log_in(:user) }

    include_examples 'requires election admin', :post, :set_by_username, topic_id: 5, usernames: ["angus"]

    context "while logged in as an admin" do
      let!(:admin) { log_in(:admin) }

      it "works with a single username in a string" do
        usernames = user1.username
        xhr :post, :set_by_username, topic_id: topic.id, usernames: usernames
        expect(response).to be_success
        json = ::JSON.parse(response.body)
        expect(json["usernames"]).to eq([usernames])
      end

      it "works with an empty string" do
        topic.custom_fields["election_nominations"] = [user1.id]
        topic.save_custom_fields(true)

        xhr :post, :set_by_username, topic_id: topic.id, usernames: ""
        expect(response).to be_success
        json = ::JSON.parse(response.body)
        expect(json["usernames"]).to eq([])
      end

      it "works with an array of usernames" do
        usernames = [user1.username, user2.username]
        xhr :post, :set_by_username, topic_id: topic.id, usernames: usernames
        expect(response).to be_success
        json = ::JSON.parse(response.body)
        expect(json["usernames"]).to eq(usernames)
      end

      it "works with an empty array" do
        topic.custom_fields["election_nominations"] = [user1.id]
        topic.save_custom_fields(true)

        xhr :post, :set_by_username, topic_id: topic.id, usernames: []
        expect(response).to be_success
        json = ::JSON.parse(response.body)
        expect(json["usernames"]).to eq([])
      end

      it "requires each username to be a real username" do
        usernames = [user1.username, "fakeuser"]
        expect { xhr :post, :set_by_username, topic_id: topic.id, usernames: usernames }
          .to raise_error(StandardError, I18n.t('election.errors.user_was_not_found', user: "fakeuser"))
      end

      it "requires more than 2 usernames if status is poll" do
        topic.custom_fields["election_status"] = Topic.election_statuses[:poll]
        topic.save_custom_fields(true)

        expect { xhr :post, :set_by_username, topic_id: topic.id, usernames: user1.username }
          .to raise_error(StandardError, I18n.t('election.errors.more_nominations'))
      end

      it "updates election post" do
        usernames = [user1.username, user2.username]
        election_post

        message = MessageBus.track_publish do
          xhr :post, :set_by_username, topic_id: topic.id, usernames: usernames
        end.find { |m| m.channel == "/topic/#{topic.id}" }

        post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])

        expect(post.raw).to include(user1.username)
        expect(post.raw).to include(user2.username)
      end

      context "has nomination statement" do
        before do
          @statement = "This is my statement"
          nomination_statement_post.raw = @statement
          nomination_statement_post.custom_fields["election_nomination_statement"] = true
          nomination_statement_post.save!

          topic.custom_fields['election_nomination_statements'] = ::JSON.generate([{
            "post_id": nomination_statement_post.id,
            "user_id": user1.id,
            "excerpt": "This is my statement"
          }])
          topic.save_custom_fields(true)

          election_post
        end

        it "retrieves existing nomination statement if nominee is re-added" do
          usernames = user1.username
          message = MessageBus.track_publish do
            xhr :post, :set_by_username, topic_id: topic.id, usernames: usernames
          end.find { |m| m.channel == "/topic/#{topic.id}" }

          post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
          expect(post.raw).to include(@statement)
        end

        it "removes nomination statement if nominee is removed" do
          topic.custom_fields["election_nominations"] = [user1.id]
          topic.save_custom_fields(true)

          message = MessageBus.track_publish do
            xhr :post, :set_by_username, topic_id: topic.id, usernames: []
          end.find { |m| m.channel == "/topic/#{topic.id}" }

          updated_post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
          expect(updated_post.raw).to_not include(@statement)

          updated_topic = Topic.find(topic.id)
          expect(updated_topic.custom_fields["election_nomination_statements"]).to eq("[]")
        end
      end
    end
  end

  describe "add" do
    context "while logged in" do
      let!(:user) { log_in(:user) }

      it "works" do
        xhr :post, :add, topic_id: topic.id
        expect(response).to be_success
        expect(Topic.find(topic.id).election_nominations).to include(user.id)
      end

      it "updates election post" do
        election_post
        message = MessageBus.track_publish do
          xhr :post, :add, topic_id: topic.id
        end.find { |m| m.channel == "/topic/#{topic.id}" }

        post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
        expect(post.raw).to include(user.username)
      end

      context 'anonymous' do
        before do
          SiteSetting.allow_anonymous_posting = true
          log_in(:anonymous)
        end

        it "does not allow anonymous users to self nominate" do
          xhr :post, :add, topic_id: topic.id
          json = ::JSON.parse(response.body)
          expect(json['failed']).to eq("FAILED")
          expect(json['message']).to eq(I18n.t('election.errors.only_named_user_can_self_nominate'))
        end
      end

      it "requires the minimum trust level" do
        SiteSetting.elections_min_trust_to_self_nominate = 2

        xhr :post, :add, topic_id: topic.id
        json = ::JSON.parse(response.body)
        expect(json['failed']).to eq("FAILED")
        expect(json['message']).to eq(I18n.t('election.errors.insufficient_trust_to_self_nominate', level: 2))
      end
    end

    it 'raises an exception when user not present' do
      expect { xhr :post, :add, topic_id: topic.id }.to raise_error(Discourse::NotLoggedIn)
    end
  end

  describe "remove" do
    context "while logged in" do
      let!(:user) { log_in(:user) }

      it "works" do
        xhr :post, :remove, topic_id: topic.id
        expect(response).to be_success
        expect(Topic.find(topic.id).election_nominations).to_not include(user.id)
      end

      it "updates election post" do
        election_post
        message = MessageBus.track_publish do
          xhr :post, :remove, topic_id: topic.id
        end.find { |m| m.channel == "/topic/#{topic.id}" }

        post = Post.find_by(topic_id: topic.id, post_number: message.data[:post_number])
        expect(post.raw).to_not include(user.username)
      end
    end

    it 'raises an exception when user not present' do
      expect { xhr :post, :remove, topic_id: topic.id }.to raise_error(Discourse::NotLoggedIn)
    end
  end
end
