class DiscourseElections::ElectionTopic
  def self.create(opts)
    title = I18n.t('election.title', position: opts[:position])
    topic = Topic.new(title: title, user: Discourse.system_user, category_id: opts[:category_id])
    topic.skip_callbacks = true
    topic.ignore_category_auto_close = true
    topic.set_or_create_timer(TopicTimer.types[:close], nil)

    topic.subtype = 'election'
    topic.custom_fields['election_status'] = Topic.election_statuses[:nomination]
    topic.custom_fields['election_position'] = opts[:position]
    topic.custom_fields['election_self_nomination_allowed'] = opts[:self_nomination_allowed] || false
    topic.custom_fields['election_nomination_message'] =  opts[:nomination_message]
    topic.custom_fields['election_poll_message'] = opts[:poll_message]

    topic.save!(validate: false)

    raw = opts[:nomination_message]
    if raw.blank?
      raw = I18n.t('election.nomination.default_message')
    end

    manager = NewPostManager.new(Discourse.system_user, {
      raw: raw,
      topic_id: topic.id,
      skip_validations: true
    })
    result = manager.perform

    if result.success?
      { topic_url: topic.url }
    else
      { error_message: I18n.t('election.errors.create_failed') }
    end
  end

  def self.set_status(topic_id, status)
    topic = Topic.find(topic_id)
    current_status = topic.election_status

    topic.custom_fields['election_status'] = status
    topic.election_status_changed = status != topic.election_status
    saved = topic.save!

    if saved && (current_status == Topic.election_statuses[:nomination] || status == Topic.election_statuses[:nomination])
      DiscourseElections::ElectionPost.rebuild_election_post(topic)
    end

    saved
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

  def self.list_category_elections(category_id, opts = {})
    query = "INNER JOIN topic_custom_fields
             ON topic_custom_fields.topic_id = topics.id
             AND topic_custom_fields.name = 'election_status'"

    if opts.try(:status)
      query << "AND topic_custom_fields.value = #{opts[:status]}"
    else
      query << "AND (topic_custom_fields.value = 'nominate' OR
                     topic_custom_fields.value = 'electing')"
    end

    if opts.try(:role)
      query << "AND topic_custom_fields.name = 'election_role'
                AND topic_custom_fields.value = #{opts[:role]}"
    end

    Topic.joins(query).where(category_id: category_id)
  end
end
