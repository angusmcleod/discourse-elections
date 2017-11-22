class DiscourseElections::ElectionTopic

  def self.create(user, opts)
    title = I18n.t('election.title', position: opts[:position].capitalize)
    topic = Topic.new(title: title, user: user, category_id: opts[:category_id])
    topic.subtype = 'election'
    topic.skip_callbacks = true
    topic.delete_topic_timer(TopicTimer.types[:close])
    topic.custom_fields['election_status'] = Topic.election_statuses[:nomination]
    topic.custom_fields['election_position'] = opts[:position]
    topic.custom_fields['election_self_nomination_allowed'] =
    topic.custom_fields['election_status_banner'] = opts[:status_banner]
    topic.custom_fields['election_status_banner_result_hours'] = opts[:status_banner_result_hours]
    topic.custom_fields['election_nomination_message'] =  opts[:nomination_message]
    topic.custom_fields['election_poll_message'] = opts[:poll_message]
    topic.custom_fields['election_poll_open'] = opts[:poll_open]
    topic.custom_fields['election_poll_open_after'] = opts[:poll_open_after]
    topic.custom_fields['election_poll_open_after_hours'] = opts[:poll_open_after_hours]
    topic.custom_fields['election_poll_open_after_nominations'] = opts[:poll_open_after_nominations]
    topic.custom_fields['election_poll_close'] = opts[:poll_close]
    topic.custom_fields['election_poll_close_after'] = opts[:poll_close_after]
    topic.custom_fields['election_poll_close_after_hours'] = opts[:poll_close_after_hours]
    topic.custom_fields['election_poll_close_time'] = opts[:poll_close_time]

    topic.save!(validate: false)

    raw = opts[:nomination_message]
    if raw.blank?
      raw = I18n.t('election.nomination.default_message')
    end

    manager = NewPostManager.new(Discourse.system_user,
      raw: raw,
      topic_id: topic.id,
      skip_validations: true
    )
    result = manager.perform

    topic.schedule_poll_open

    if result.success?
      { url: topic.relative_url }
    else
      { error_message: I18n.t('election.errors.create_failed') }
    end
  end

  def self.set_status(topic_id, status)
    topic = Topic.find(topic_id)
    current_status = topic.election_status

    topic.custom_fields['election_status'] = status
    topic.election_status_changed = status != current_status
    topic.save!

    if current_status == Topic.election_statuses[:nomination] || status == Topic.election_statuses[:nomination]
      DiscourseElections::ElectionPost.rebuild_election_post(topic)
    end

    topic.election_status
  end

  def self.set_message(topic_id, message, type, same_message = nil)
    topic = Topic.find(topic_id)
    topic.custom_fields["election_#{type}_message"] = message
    saved = topic.save!

    if saved && topic.election_status == Topic.election_statuses[type.to_sym]
      DiscourseElections::ElectionPost.rebuild_election_post(topic)
    end

    saved
  end

  def self.set_position(topic_id, position)
    topic = Topic.find(topic_id)
    topic.title = I18n.t('election.title', position: position)
    topic.custom_fields["election_position"] = position
    saved = topic.save!

    if saved
      MessageBus.publish("/topic/#{topic_id}", reload_topic: true)
    end

    saved
  end
end
