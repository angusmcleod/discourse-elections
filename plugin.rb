# name: discourse-elections
# about: Run elections in Discourse
# version: 0.2.1
# authors: angusmcleod
# url: https://github.com/angusmcleod/discourse-elections

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
  Category.register_custom_field_type('for_elections', :boolean)
  Post.register_custom_field_type('election_nomination_statement', :boolean)

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
  load File.expand_path('../lib/election.rb', __FILE__)
  load File.expand_path('../lib/election_post.rb', __FILE__)
  load File.expand_path('../lib/election_time.rb', __FILE__)
  load File.expand_path('../lib/election_topic.rb', __FILE__)
  load File.expand_path('../lib/election_user.rb', __FILE__)
  load File.expand_path('../lib/election_category.rb', __FILE__)
  load File.expand_path('../lib/nomination_statement.rb', __FILE__)
  load File.expand_path('../lib/nomination.rb', __FILE__)
  load File.expand_path('../lib/poll_edits.rb', __FILE__)

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

  add_to_serializer(:topic_view, :subtype) { object.topic.subtype }
  add_to_serializer(:topic_view, :election_status) { object.topic.election_status }
  add_to_serializer(:topic_view, :include_election_status?) { object.topic.election }
  add_to_serializer(:topic_view, :election_position) { object.topic.election_position }
  add_to_serializer(:topic_view, :include_election_position?) { object.topic.election }
  add_to_serializer(:topic_view, :election_nominations) { object.topic.election_nominations }
  add_to_serializer(:topic_view, :include_election_nominations?) { object.topic.election }
  add_to_serializer(:topic_view, :election_nominations_usernames) { object.topic.election_nominations_usernames }
  add_to_serializer(:topic_view, :include_election_nominations_usernames?) { object.topic.election }
  add_to_serializer(:topic_view, :election_self_nomination_allowed) { object.topic.election_self_nomination_allowed }
  add_to_serializer(:topic_view, :include_election_self_nomination_allowed?) { object.topic.election }
  add_to_serializer(:topic_view, :election_can_self_nominate) do
    scope.user && !scope.user.anonymous? &&
    (scope.is_admin? || scope.user.trust_level >= SiteSetting.elections_min_trust_to_self_nominate.to_i)
  end
  add_to_serializer(:topic_view, :include_election_can_self_nominate?) { object.topic.election }
  add_to_serializer(:topic_view, :election_is_nominee) do
    scope.user && object.topic.election_nominations.include?(scope.user.id)
  end
  add_to_serializer(:topic_view, :include_election_is_nominee?) { object.topic.election }
  add_to_serializer(:topic_view, :election_nomination_statements) { object.topic.election_nomination_statements }
  add_to_serializer(:topic_view, :include_election_nomination_statements?) { object.topic.election }
  add_to_serializer(:topic_view, :election_made_statement) do
    if scope.user
      object.topic.election_nomination_statements.any? { |n| n['user_id'] == scope.user.id }
    end
  end
  add_to_serializer(:topic_view, :include_election_made_statement?) { object.topic.election }
  add_to_serializer(:topic_view, :election_nomination_message) { object.topic.custom_fields['election_nomination_message'] }
  add_to_serializer(:topic_view, :include_election_nomination_message?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_message) { object.topic.custom_fields['election_poll_message'] }
  add_to_serializer(:topic_view, :include_election_poll_message?) { object.topic.election }
  add_to_serializer(:topic_view, :election_closed_poll_message) { object.topic.custom_fields['election_closed_poll_message'] }
  add_to_serializer(:topic_view, :include_election_closed_poll_message?) { object.topic.election }
  add_to_serializer(:topic_view, :election_same_message) { object.topic.custom_fields['election_poll_message'] }
  add_to_serializer(:topic_view, :include_election_same_message?) { object.topic.election }
  add_to_serializer(:topic_view, :election_status_banner) { object.topic.custom_fields['election_status_banner'] }
  add_to_serializer(:topic_view, :include_election_status_banner?) { object.topic.election }
  add_to_serializer(:topic_view, :election_status_banner_result_hours) { object.topic.custom_fields['election_status_banner_result_hours'] }
  add_to_serializer(:topic_view, :include_election_status_banner_result_hours?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open) { object.topic.election_poll_open }
  add_to_serializer(:topic_view, :include_election_poll_open?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open_after) { object.topic.election_poll_open_after }
  add_to_serializer(:topic_view, :include_election_poll_open_after?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open_after_hours) { object.topic.election_poll_open_after_hours }
  add_to_serializer(:topic_view, :include_election_poll_open_after_hours?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open_after_nominations) { object.topic.election_poll_open_after_nominations }
  add_to_serializer(:topic_view, :include_election_poll_open_after_nominations?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open_time) { object.topic.election_poll_open_time }
  add_to_serializer(:topic_view, :include_election_poll_open_time?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_open_scheduled) { object.topic.election_poll_open_scheduled }
  add_to_serializer(:topic_view, :include_election_poll_open_scheduled?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close) { object.topic.election_poll_close }
  add_to_serializer(:topic_view, :include_election_poll_close?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close_after) { object.topic.election_poll_close_after }
  add_to_serializer(:topic_view, :include_election_poll_close_after?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close_after_hours) { object.topic.election_poll_close_after_hours }
  add_to_serializer(:topic_view, :include_election_poll_close_after_hours?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close_after_voters) { object.topic.election_poll_close_after_voters }
  add_to_serializer(:topic_view, :include_election_poll_close_after_voters?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close_time) { object.topic.election_poll_close_time }
  add_to_serializer(:topic_view, :include_election_poll_close_time?) { object.topic.election }
  add_to_serializer(:topic_view, :election_poll_close_scheduled) { object.topic.election_poll_close_scheduled }
  add_to_serializer(:topic_view, :include_election_poll_close_scheduled?) { object.topic.election }
  add_to_serializer(:topic_view, :election_winner) { object.topic.election_winner }
  add_to_serializer(:topic_view, :include_election_winner?) { object.topic.election }


  add_to_serializer(:basic_category, :for_elections) { object.custom_fields['for_elections'] }
  add_to_serializer(:basic_category, :election_list) { object.election_list }
  add_to_serializer(:basic_category, :include_election_list?) { object.election_list.present? }

  [
    "for_elections",
    "election_list",
  ].each do |key|
    Site.preloaded_category_custom_fields << key if Site.respond_to? :preloaded_category_custom_fields
  end

  add_to_serializer(:post, :election_post) { object.is_first_post? }
  add_to_serializer(:post, :include_election_post?) { object.topic.election }
  add_to_serializer(:post, :election_nomination_statement) { object.election_nomination_statement }
  add_to_serializer(:post, :include_election_nomination_statement?) { object.topic.election }
  add_to_serializer(:post, :election_nominee_title) { object.user.election_nominee_title }
  add_to_serializer(:post, :include_election_nominee_title?) { object.user && object.user.election_nominations.present? }
  add_to_serializer(:post, :election_by_nominee) do
    object.user && object.topic.election_nominations.include?(object.user.id)
  end
  add_to_serializer(:post, :include_election_by_nominee?) { object.topic.election }
  add_to_serializer(:current_user, :is_elections_admin) { object.is_elections_admin? }

  DiscourseEvent.trigger(:elections_ready)
end
