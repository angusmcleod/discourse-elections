# name: discourse-elections
# about: Run elections in Discourse
# version: 0.1
# authors: angus

register_asset 'stylesheets/discourse-elections.scss'

after_initialize do
  Topic.register_custom_field_type('election_self_nomination', :boolean)

  add_to_serializer(:topic_view, :election_status) {object.topic.custom_fields['election_status']}
  add_to_serializer(:topic_view, :election_position) {object.topic.custom_fields['election_position']}
  add_to_serializer(:topic_view, :election_details_url) {object.topic.custom_fields['election_details_url']}
  add_to_serializer(:topic_view, :election_nominations) {object.topic.election_nominations}
  add_to_serializer(:topic_view, :election_self_nomination_allowed) {object.topic.custom_fields['election_self_nomination_allowed']}
  add_to_serializer(:topic_view, :subtype) {object.topic.subtype}
  add_to_serializer(:topic_view, :election_is_nominated) {
    if scope.user
      object.topic.election_nominations.include?(scope.user.username)
    end
  }
  add_to_serializer(:topic_view, :election_nomination_statements) {object.topic.election_nomination_statements}
  add_to_serializer(:topic_view, :election_made_statement) {
    if scope.user
      object.topic.election_nomination_statements.any?{|n| n['username'] == scope.user.username}
    end
  }

  add_to_serializer(:basic_category, :for_elections) {object.custom_fields["for_elections"]}

  Post.register_custom_field_type('election_nomination_statement', :boolean)
  add_to_serializer(:post, :election_post) {object.is_first_post?}
  add_to_serializer(:post, :election_nomination_statement) {object.custom_fields["election_nomination_statement"]}
  add_to_serializer(:post, :election_is_nominee) {
    if object.user
      object.topic.election_nominations.include?(object.user.username)
    end
  }

  require_dependency "application_controller"
  module ::DiscourseElections
    class Engine < ::Rails::Engine
      engine_name "discourse_elections"
      isolate_namespace DiscourseElections
    end
  end

  load File.expand_path('../lib/handler.rb', __FILE__)

  DiscourseElections::Engine.routes.draw do
    post "nominations" => "election#set_nominations"
    post "nomination" => "election#add_nomination"
    delete "nomination" => "election#remove_nomination"
    post "create" =>"election#create_election"
    put "start" => "election#start_election"
    get ":category_id" => "election#category_elections"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseElections::Engine, at: "election"
  end

  class DiscourseElections::ElectionController < ::ApplicationController
    def create_election
      params.require(:category_id)
      params.require(:position)
      params.permit(:details_url)
      params.permit(:message)
      params.permit(:self_nomination)

      unless current_user.try(:elections_admin?)
        raise StandardError.new I18n.t("election.errors.not_authorized")
      end

      result = DiscourseElections::Handler.create_election_topic(
                params[:category_id],
                params[:position],
                params[:details_url],
                params[:message],
                params[:self_nomination_allowed])

      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json.merge(topic_url: result[:topic_url])
      end
    end

    def start_election
      params.require(:topic_id)

      unless current_user.try(:elections_admin?)
        raise StandardError.new I18n.t("election.errors.not_authorized")
      end

      result = DiscourseElections::Handler.start_election(params[:topic_id])

      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json
      end
    end

    def set_nominations
      params.require(:topic_id)
      params.permit(:usernames)

      result = DiscourseElections::Handler.set_nominations(params[:topic_id], params[:usernames])

      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json
      end
    end

    def add_nomination
      params.require(:topic_id)

      result = DiscourseElections::Handler.add_nomination(params[:topic_id], current_user.username)

      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json
      end
    end

    def remove_nomination
      params.require(:topic_id)

      result = DiscourseElections::Handler.remove_nomination(params[:topic_id], current_user.username)

      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json
      end
    end

    def category_elections
      params.require(:category_id)

      topics = DiscourseElections::Handler.category_elections(params[:category_id])

      render_serialized(topics, DiscourseElections::ElectionSerializer)
    end
  end

  class DiscourseElections::ElectionSerializer < ApplicationSerializer
    attributes :position, :url, :status

    def position
      object.custom_fields['election_position']
    end

    def status
      object.custom_fields['election_status']
    end
  end

  User.class_eval do
    def elections_admin?
      if SiteSetting.elections_admin_moderator
        staff?
      else
        admin?
      end
    end
  end

  add_to_serializer(:current_user, :is_elections_admin) {object.elections_admin?}

  PostRevisor.track_topic_field(:election_status)

  PostRevisor.class_eval do
    track_topic_field(:election_status) do |tc, status|
      tc.record_change('election_status', tc.topic.custom_fields['election_status'], status)
      tc.topic.custom_fields['election_status'] = status
      tc.topic.election_status_changed = true
    end
  end

  PostCustomField.class_eval do
    after_save :update_election_status, if: :polls_updated

    def polls_updated
      self.name == 'polls'
    end

    def update_election_status
      poll = JSON.parse(self.value)["poll"]
      post = Post.find(self.post_id)
      election_status = post.topic.custom_fields['election_status']

      if poll["status"] == 'closed'
        post.topic.custom_fields['election_status'] = 'closed'
        post.topic.election_status_changed = true
        post.topic.save!
      end

      if election_status == 'closed' && poll["status"] != 'closed'
        post.topic.custom_fields['election_status'] = 'electing'
        post.topic.election_status_changed = true
        post.topic.save!
      end
    end
  end

  Topic.class_eval do
    attr_accessor :election_status_changed
    after_save :refresh_topic, if: :election_status_changed
    after_save :notify_nominees, if: :election_status_changed

    def refresh_topic
      MessageBus.publish("/topic/#{self.id}", reload_topic: true, refresh_stream: true)
      election_status_changed = false
    end

    def notify_nominees
      status = self.custom_fields['election_status']

      if status === 'electing' || status === 'closed'

        description = ''

        if status === 'electing'
          description = I18n.t('election.notification.electing', title: self.title, status: status)
        end

        if status === 'closed'
          description = I18n.t('election.notification.closed', title: self.title, status: status)
        end

        election_nominations.each do |username|
          user = User.find_by(username: username)
          user.notifications.create(notification_type: Notification.types[:custom],
                                    data: { topic_id: self.id,
                                            message: "election.nomination.notification",
                                            description: description }.to_json)
        end
      end
    end

    def election_nominations
      if self.custom_fields["election_nominations"]
        self.custom_fields["election_nominations"].split('|')
      else
        []
      end
    end

    def election_nomination_statements
      if self.custom_fields["election_nomination_statements"]
        JSON.parse(self.custom_fields["election_nomination_statements"])
      else
        []
      end
    end
  end

  PostRevisor.track_topic_field(:election_details_url)

  PostRevisor.class_eval do
    track_topic_field(:election_details_url) do |tc, url|
      tc.record_change('election_details_url', tc.topic.custom_fields['election_details_url'], url)
      tc.topic.custom_fields['election_details_url'] = url
    end
  end

  NewPostManager.add_handler do |manager|
    if manager.args[:topic_id]
      topic = Topic.find(manager.args[:topic_id])

      # do nothing if first post in topic
      if topic.subtype === 'election' && topic.try(:highest_post_number) != 0
        extracted_polls = DiscoursePoll::Poll::extract(manager.args[:raw], manager.args[:topic_id], manager.user[:id])

        if extracted_polls.length > 0
          result = NewPostResult.new(:poll, false)

          result.errors[:base] = I18n.t("election.errors.seperate_poll")

          result
        end
      end
    end
  end

  validate(:post, :validate_election_polls) do |force = nil|
    return unless self.raw_changed?
    return if self.is_first_post?

    extracted_polls = DiscoursePoll::Poll::extract(self.raw, self.topic_id, self.user_id)

    if extracted_polls.length > 0
      self.errors.add(:base, I18n.t("election.errors.seperate_poll"))
    end
  end

  PostRevisor.track_topic_field(:election_nomination_statement)

  DiscourseEvent.on(:post_created) do |post, opts, user|
    if opts[:election_nomination_statement] && post.topic.election_nominations.include?(user.username)
      post.custom_fields['election_nomination_statement'] = opts[:election_nomination_statement]
      post.save

      DiscourseElections::Handler.update_nomination_statement(post)
    end
  end

  DiscourseEvent.on(:post_edited) do |post, topic_changed|
    user = User.find(post.user_id)
    if post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.username)
      DiscourseElections::Handler.update_nomination_statement(post)
    end
  end

  DiscourseEvent.on(:post_destroyed) do |post, opts, user|
    if post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.username)
      DiscourseElections::Handler.update_nomination_statement(post)
    end
  end

  DiscourseEvent.on(:post_recovered) do |post, opts, user|
    if post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.username)
      DiscourseElections::Handler.update_nomination_statement(post)
    end
  end
end
