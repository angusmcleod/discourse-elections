class DiscourseElections::ElectionTopic
  def self.create(category_id, position, details_url, message, self_nomination_allowed)
    category = Category.find(category_id)
    title = I18n.t('election.title', position: position)

    topic = Topic.new(title: title, user: Discourse.system_user, category_id: category.id)
    topic.skip_callbacks = true
    topic.ignore_category_auto_close = true
    topic.set_or_create_timer(TopicTimer.types[:close], nil)

    topic.subtype = 'election'
    topic.custom_fields['election_status'] = 'nominate'
    topic.custom_fields['election_position'] = position
    topic.custom_fields['election_nominations'] = []
    topic.custom_fields['election_self_nomination_allowed'] = self_nomination_allowed || false

    if details_url
      topic.custom_fields['election_details_url'] = details_url
    end

    if message
      topic.custom_fields['election_nomination_message'] = message
    end

    topic.save!(validate: false)

    raw = "#{I18n.t('election.nominate.desc')}\n\n"

    if message
      raw << message
    end

    manager = NewPostManager.new(Discourse.system_user, {
      raw: raw,
      topic_id: topic.id,
      cook_method: Post.cook_methods[:raw_html]
    })
    result = manager.perform

    if result.success?
      { topic_url: topic.url }
    else
      { error_message: "Election creation failed" }
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
