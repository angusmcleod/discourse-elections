require "rails_helper"

describe ::DiscourseElections::NominationController do
  routes { ::DiscourseElections::Engine.routes }

  let(:user1) { Fabricate(:user) }
  let(:user2) { Fabricate(:user) }

  let(:category) { Fabricate(:category, custom_fields: { for_elections: true }) }
  let(:topic) { Fabricate(:topic, subtype: 'election',
                                  category_id: category.id,
                                  title: I18n.t('election.title', position: 'Moderator'),
                                  user: Discourse.system_user,
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
