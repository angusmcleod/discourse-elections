# name: discourse-elections
# about: Run elections in Discourse
# version: 0.2
# authors: angus

register_asset 'stylesheets/common/elections.scss'
register_asset 'stylesheets/desktop/elections.scss', :desktop
register_asset 'stylesheets/mobile/elections.scss', :mobile
register_asset 'lib/jquery.timepicker.min.js'
register_asset 'lib/jquery.timepicker.scss'

enabled_site_setting :elections_enabled

after_initialize do
  Topic.register_custom_field_type('election_self_nomination_allowed', :boolean)
  Topic.register_custom_field_type('election_nominations', :integer)
  Topic.register_custom_field_type('election_status', :integer)
  Topic.register_custom_field_type('election_status_banner', :boolean)
  Topic.register_custom_field_type('election_status_banner_result_hours', :integer)
  Topic.register_custom_field_type('election_poll_open', :boolean)
  Topic.register_custom_field_type('election_poll_open_after', :boolean)
  Topic.register_custom_field_type('election_poll_open_after_hours', :integer)
  Topic.register_custom_field_type('election_poll_open_after_nominations', :integer)
  Topic.register_custom_field_type('election_poll_open_scheduled', :boolean)
  Topic.register_custom_field_type('election_poll_close', :boolean)
  Topic.register_custom_field_type('election_poll_close_after', :boolean)
  Topic.register_custom_field_type('election_poll_close_after_hours', :integer)
  Topic.register_custom_field_type('election_poll_close_after_voters', :integer)
  Topic.register_custom_field_type('election_poll_close_scheduled', :boolean)
  add_to_serializer(:topic_view, :subtype) { object.topic.subtype }
  add_to_serializer(:topic_view, :election_status) { object.topic.election_status }
  add_to_serializer(:topic_view, :election_position) { object.topic.custom_fields['election_position'] }
  add_to_serializer(:topic_view, :election_nominations) { object.topic.election_nominations }
  add_to_serializer(:topic_view, :election_nominations_usernames) { object.topic.election_nominations_usernames }
  add_to_serializer(:topic_view, :election_self_nomination_allowed) { object.topic.custom_fields['election_self_nomination_allowed'] }
  add_to_serializer(:topic_view, :election_can_self_nominate) do
    scope.user && !scope.user.anonymous? &&
    (scope.is_admin? || scope.user.trust_level >= SiteSetting.elections_min_trust_to_self_nominate.to_i)
  end
  add_to_serializer(:topic_view, :election_is_nominee) do
    scope.user && object.topic.election_nominations.include?(scope.user.id)
  end
  add_to_serializer(:topic_view, :election_nomination_statements) { object.topic.election_nomination_statements }
  add_to_serializer(:topic_view, :election_made_statement) do
    if scope.user
      object.topic.election_nomination_statements.any? { |n| n['user_id'] == scope.user.id }
    end
  end
  add_to_serializer(:topic_view, :election_nomination_message) { object.topic.custom_fields['election_nomination_message'] }
  add_to_serializer(:topic_view, :election_poll_message) { object.topic.custom_fields['election_poll_message'] }
  add_to_serializer(:topic_view, :election_closed_poll_message) { object.topic.custom_fields['election_closed_poll_message'] }
  add_to_serializer(:topic_view, :election_same_message) { object.topic.custom_fields['election_poll_message'] }
  add_to_serializer(:topic_view, :election_status_banner) { object.topic.custom_fields['election_status_banner'] }
  add_to_serializer(:topic_view, :election_status_banner_result_hours) { object.topic.custom_fields['election_status_banner_result_hours'] }

  add_to_serializer(:topic_view, :election_poll_open) { object.topic.election_poll_open }
  add_to_serializer(:topic_view, :election_poll_open_after) { object.topic.election_poll_open_after }
  add_to_serializer(:topic_view, :election_poll_open_after_hours) { object.topic.election_poll_open_after_hours }
  add_to_serializer(:topic_view, :election_poll_open_after_nominations) { object.topic.election_poll_open_after_nominations }
  add_to_serializer(:topic_view, :election_poll_open_time) { object.topic.election_poll_open_time }
  add_to_serializer(:topic_view, :election_poll_open_scheduled) { object.topic.election_poll_open_scheduled }
  add_to_serializer(:topic_view, :election_poll_close) { object.topic.election_poll_close }
  add_to_serializer(:topic_view, :election_poll_close_after) { object.topic.election_poll_close_after }
  add_to_serializer(:topic_view, :election_poll_close_after_hours) { object.topic.election_poll_close_after_hours }
  add_to_serializer(:topic_view, :election_poll_close_after_voters) { object.topic.election_poll_close_after_voters }
  add_to_serializer(:topic_view, :election_poll_close_time) { object.topic.election_poll_close_time }
  add_to_serializer(:topic_view, :election_poll_close_scheduled) { object.topic.election_poll_close_scheduled }

  Category.register_custom_field_type('for_elections', :boolean)
  add_to_serializer(:basic_category, :for_elections) { object.custom_fields['for_elections'] }
  add_to_serializer(:basic_category, :election_list) { object.election_list }
  add_to_serializer(:basic_category, :include_election_list?) { object.election_list.present? }

  Post.register_custom_field_type('election_nomination_statement', :boolean)
  add_to_serializer(:post, :election_post) { object.topic.election && object.is_first_post? }
  add_to_serializer(:post, :election_nomination_statement) { object.custom_fields['election_nomination_statement'] }
  add_to_serializer(:post, :election_nominee_title) do
    object.user && object.user.election_nominations && object.user.election_nominee_title
  end
  add_to_serializer(:post, :election_by_nominee) do
    object.user && object.topic.election_nominations.include?(object.user.id)
  end
  PostRevisor.track_topic_field(:election_nomination_statement)

  add_to_serializer(:current_user, :is_elections_admin) { object.is_elections_admin? }

  require_dependency 'application_controller'
  module ::DiscourseElections
    class Engine < ::Rails::Engine
      engine_name 'discourse_elections'
      isolate_namespace DiscourseElections
    end
  end

  DiscourseElections::Engine.routes.draw do
    post 'nomination/set-by-username' => 'nomination#set_by_username'
    post 'nomination' => 'nomination#add'
    delete 'nomination' => 'nomination#remove'

    post 'create' => 'election#create'
    put 'set-self-nomination-allowed' => 'election#set_self_nomination_allowed'
    put 'set-status-banner' => 'election#set_status_banner'
    put 'set-status-banner-result-hours' => 'election#set_status_banner_result_hours'
    put 'set-nomination-message' => 'election#set_message'
    put 'set-poll-message' => 'election#set_message'
    put 'set-closed-poll-message' => 'election#set_message'
    put 'set-status' => 'election#set_status'
    put 'set-position' => 'election#set_position'
    put 'set-poll-time' => 'election#set_poll_time'
    put 'start-poll' => 'election#start_poll'
    get 'category-list' => 'list#category_list'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseElections::Engine, at: 'election'
  end

  load File.expand_path('../controllers/base.rb', __FILE__)
  load File.expand_path('../controllers/election.rb', __FILE__)
  load File.expand_path('../controllers/list.rb', __FILE__)
  load File.expand_path('../controllers/nomination.rb', __FILE__)
  load File.expand_path('../serializers/election.rb', __FILE__)
  load File.expand_path('../jobs/election_notify_moderators.rb', __FILE__)
  load File.expand_path('../jobs/election_notify_nominees.rb', __FILE__)
  load File.expand_path('../jobs/election_remove_from_category_list.rb', __FILE__)
  load File.expand_path('../jobs/election_open_poll.rb', __FILE__)
  load File.expand_path('../jobs/election_close_poll.rb', __FILE__)
  load File.expand_path('../lib/election_post.rb', __FILE__)
  load File.expand_path('../lib/election_time.rb', __FILE__)
  load File.expand_path('../lib/election_topic.rb', __FILE__)
  load File.expand_path('../lib/election_category.rb', __FILE__)
  load File.expand_path('../lib/nomination_statement.rb', __FILE__)
  load File.expand_path('../lib/nomination.rb', __FILE__)
  load File.expand_path('../lib/poll_edits.rb', __FILE__)

  Category.class_eval do
    def election_list
      if list = self.custom_fields['election_list']
        list = ::JSON.parse(list) if list.is_a?(String)
        [list].flatten
      else
        []
      end
    end
  end

  User.class_eval do
    def is_elections_admin?
      if SiteSetting.elections_admin_moderator
        staff?
      else
        admin?
      end
    end

    def election_nominations
      TopicCustomField.where(name: 'election_nominations', value: id).pluck(:topic_id) || []
    end

    def election_nominee_title
      if election_nominations.any?
        topic = Topic.find(election_nominations[0])
        I18n.t('election.post.nominee_title',
          url: topic.url,
          position: topic.custom_fields['election_position'])
      end
    end
  end

  PostCustomField.class_eval do
    after_save :update_election_status, if: :polls_updated

    def polls_updated
      name == 'polls'
    end

    def update_election_status
      return unless SiteSetting.elections_enabled

      poll = JSON.parse(value)['poll']
      post = Post.find(post_id)
      new_status = nil

      if poll['status'] == 'closed' && post.topic.election_status == Topic.election_statuses[:poll]
        new_status = Topic.election_statuses[:closed_poll]
      end

      if poll['status'] == 'open' && post.topic.election_status == Topic.election_statuses[:closed_poll]
        new_status = Topic.election_statuses[:poll]
      end

      if new_status
        result = DiscourseElections::ElectionTopic.set_status(post.topic_id, new_status)

        if result
          DiscourseElections::ElectionTopic.refresh(post.topic.id)
        end
      end
    end
  end

  Topic.class_eval do
    attr_accessor :election_status_changed, :election_status, :election_post
    after_save :handle_election_status_change, if: :election_status_changed

    def election
      Topic.election_statuses.has_value? election_status
    end

    def election_post
      posts.find_by(post_number: 1)
    end

    def election_status
      self.custom_fields['election_status'].to_i
    end

    def election_position
      self.custom_fields['election_position']
    end

    def election_status_banner
      self.custom_fields['election_status_banner']
    end

    def election_status_banner_result_hours
      self.custom_fields['election_status_banner_result_hours'].to_i
    end

    def election_poll_open
      self.custom_fields['election_poll_open']
    end

    def election_poll_open_after
      self.custom_fields['election_poll_open_after']
    end

    def election_poll_open_after_hours
      self.custom_fields['election_poll_open_after_hours'].to_i
    end

    def election_poll_open_after_nominations
      self.custom_fields['election_poll_open_after_nominations'].to_i
    end

    def election_poll_open_time
      self.custom_fields['election_poll_open_time']
    end

    def election_poll_open_scheduled
      self.custom_fields['election_poll_open_scheduled']
    end

    def election_poll_close
      self.custom_fields['election_poll_close']
    end

    def election_poll_close_after
      self.custom_fields['election_poll_close_after']
    end

    def election_poll_close_after_hours
      self.custom_fields['election_poll_close_after_hours'].to_i
    end

    def election_poll_close_after_voters
      self.custom_fields['election_poll_close_after_voters'].to_i
    end

    def election_poll_close_time
      self.custom_fields['election_poll_close_time']
    end

    def election_poll_close_scheduled
      self.custom_fields['election_poll_close_scheduled']
    end

    def election_poll_voters
      if polls = election_post.custom_fields['polls']
        polls['poll']['voters'].to_i
      else
        0
      end
    end

    def handle_election_status_change
      return unless SiteSetting.elections_enabled

      if election_status === Topic.election_statuses[:nomination]
        DiscourseElections::ElectionCategory.update_election_list(self.category_id, self.id, status: election_status)
        DiscourseElections::ElectionTime.cancel_scheduled_poll_close(self)
      end

      if election_status === Topic.election_statuses[:poll]
        DiscourseElections::ElectionPost.update_poll_status(self)
        DiscourseElections::ElectionCategory.update_election_list(self.category_id, self.id, status: election_status)
        DiscourseElections::Nomination.notify_nominees(self.id, 'poll')
        DiscourseElections::ElectionTopic.notify_moderators(self.id, 'poll')
        DiscourseElections::ElectionTime.set_poll_open_now(self)
        DiscourseElections::ElectionTime.cancel_scheduled_poll_open(self)
      end

      if election_status === Topic.election_statuses[:closed_poll]
        DiscourseElections::ElectionPost.update_poll_status(self)
        DiscourseElections::ElectionCategory.update_election_list(self.category_id, self.id, status: election_status)
        DiscourseElections::Nomination.notify_nominees(self.id, 'closed_poll')
        DiscourseElections::ElectionTopic.notify_moderators(self.id, 'closed_poll')
        DiscourseElections::ElectionTime.cancel_scheduled_poll_close(self)
      end

      election_status_changed = false
    end

    def election_nominations
      if custom_fields['election_nominations']
        [*custom_fields['election_nominations']]
      else
        []
      end
    end

    def election_nominations_usernames
      if election_nominations.any?
        usernames = []
        election_nominations.each do |user_id|
          usernames.push(User.find(user_id).username) if user_id
        end
        usernames
      else
        []
      end
    end

    def election_nomination_statements
      if custom_fields['election_nomination_statements']
        JSON.parse(custom_fields['election_nomination_statements'])
      else
        []
      end
    end

    def self.election_statuses
      @types ||= Enum.new(nomination: 1,
                          poll: 2,
                          closed_poll: 3)
    end
  end

  NewPostManager.add_handler do |manager|
    if SiteSetting.elections_enabled && manager.args[:topic_id]
      topic = Topic.find(manager.args[:topic_id])

      # do nothing if first post in topic
      if topic.subtype === 'election' && topic.try(:highest_post_number) != 0
        extracted_polls = DiscoursePoll::Poll.extract(manager.args[:raw], manager.args[:topic_id], manager.user[:id])

        unless extracted_polls.empty?
          result = NewPostResult.new(:poll, false)
          result.errors[:base] = I18n.t('election.errors.seperate_poll')
          result
        end
      end
    end
  end

  validate(:post, :validate_election_polls) do |_force = nil|
    return unless raw_changed?
    return if is_first_post?
    return unless self.topic.subtype === 'election'
    return unless SiteSetting.elections_enabled

    extracted_polls = DiscoursePoll::Poll.extract(raw, topic_id, user_id)

    unless extracted_polls.empty?
      errors.add(:base, I18n.t('election.errors.seperate_poll'))
    end
  end

  DiscourseEvent.on(:post_created) do |post, opts, user|
    if SiteSetting.elections_enabled && opts[:election_nomination_statement] && post.topic.election_nominations.include?(user.id)
      post.custom_fields['election_nomination_statement'] = opts[:election_nomination_statement]
      post.save_custom_fields(true)

      DiscourseElections::NominationStatement.update(post)
    end
  end

  DiscourseEvent.on(:post_edited) do |post, _topic_changed|
    user = User.find(post.user_id)
    if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
      DiscourseElections::NominationStatement.update(post)
    end
  end

  DiscourseEvent.on(:post_destroyed) do |post, _opts, user|
    if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
      DiscourseElections::NominationStatement.update(post)
    end
  end

  DiscourseEvent.on(:post_recovered) do |post, _opts, user|
    if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
      DiscourseElections::NominationStatement.update(post)
    end
  end
end
