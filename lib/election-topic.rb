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

    nomination_message = opts[:nomination_message] ? opts[:nomination_message] : I18n.t('election.nomination.default_message')
    topic.custom_fields['election_nomination_message'] = nomination_message

    if opts[:election_message]
      topic.custom_fields['election_message'] = opts[:election_message]
    end

    topic.save!(validate: false)

    manager = NewPostManager.new(Discourse.system_user, {
      raw: nomination_message,
      topic_id: topic.id,
      cook_method: Post.cook_methods[:raw_html]
    })
    result = manager.perform

    if result.success?
      { topic_url: topic.url }
    else
      { error_message: I18n.t('election.errors.create_failed') }
    end
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
