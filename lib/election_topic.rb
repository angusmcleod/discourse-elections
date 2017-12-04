class DiscourseElections::ElectionTopic

  def self.create(user, opts)
    title = I18n.t('election.title', position: opts[:position].capitalize)
    topic = Topic.new(title: title, user: user, category_id: opts[:category_id])
    topic.subtype = 'election'
    topic.skip_callbacks = true
    custom_fields = {
      election_status: Topic.election_statuses[:nomination],
      election_position: opts[:position],
      election_self_nomination_allowed: opts[:self_nomination_allowed] || false,
      election_status_banner: opts[:status_banner] || false,
      election_poll_open: opts[:poll_open] || false,
      election_poll_close: opts[:poll_close] || false,
      election_nomination_message: opts[:nomination_message] || '',
      election_poll_message: opts[:poll_message] || '',
      election_closed_poll_message: opts[:closed_poll_message] || ''
    }

    topic.custom_fields = custom_fields

    if opts[:status_banner]
      topic.custom_fields['election_status_banner_result_hours'] = opts[:status_banner_result_hours]
    end

    if opts[:poll_open]
      if topic.custom_fields['election_poll_open_after'] = opts[:poll_open_after] || false
        topic.custom_fields['election_poll_open_after_hours'] = opts[:poll_open_after_hours]
        topic.custom_fields['election_poll_open_after_nominations'] = opts[:poll_open_after_nominations]
      else
        topic.custom_fields['election_poll_open_time'] = opts[:poll_open_time]
      end
    end

    if opts[:poll_close]
      if topic.custom_fields['election_poll_close_after'] = opts[:poll_close_after] || false
        topic.custom_fields['election_poll_close_after_hours'] = opts[:poll_close_after_hours]
      else
        topic.custom_fields['election_poll_close_time'] = opts[:poll_close_time]
      end
    end

    topic.save!(validate: false)

    if topic.election_poll_open && !topic.election_poll_open_after && topic.election_poll_open_time
      topic.schedule_poll_open
    end

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

    DiscourseElections::ElectionCategory.update_election_list(
      topic.category_id,
      topic.id,
      status: topic.election_status
    )

    if result.success?
      { url: topic.relative_url }
    else
      { error_message: I18n.t('election.errors.create_failed') }
    end
  end

  def self.set_status(topic_id, status, unattended = false)
    topic = Topic.find(topic_id)
    current_status = topic.election_status

    topic.custom_fields['election_status'] = status
    topic.election_status_changed = status != current_status
    topic.save!

    if status != current_status
      DiscourseElections::ElectionPost.rebuild_election_post(topic, unattended)
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
      self.refresh(topic_id)
    end

    saved
  end

  def self.notify_moderators(topic_id, type)
    Jobs.enqueue(:election_notify_moderators, topic_id: topic_id, type: type)
  end

  def self.refresh(topic_id)
    MessageBus.publish("/topic/#{topic_id}", reload_topic: true)
  end

  def self.moderators(topic_id)
    topic = Topic.find(topic_id)
    moderators = User.where(moderator: true).human_users
    category_moderators = moderators.select do |u|
      u.custom_fields['moderator_category_id'].to_i === topic.category_id.to_i
    end

    if category_moderators.any?
      category_moderators
    else
      moderators.select { |u| u.custom_fields['moderator_category_id'].blank? }
    end
  end
end
