class DiscourseElections::Handler
  def self.create_election_topic(category_id, position, details_url)
    category = Category.find(category_id)
    title = "#{category.name} #{position} #{I18n.t('election.title')}"

    topic = Topic.new(title: title, user: Discourse.system_user, category_id: category.id)
    topic.skip_callbacks = true
    topic.ignore_category_auto_close = true
    topic.set_or_create_timer(TopicTimer.types[:close], nil)

    topic.subtype = 'election'
    topic.custom_fields['election_status'] = 'nominate'
    topic.custom_fields['election_position'] = position
    topic.custom_fields['election_nominations'] = []

    if details_url
      topic.custom_fields['election_details_url'] = details_url
    end

    topic.save!(validate: false)

    manager = NewPostManager.new(Discourse.system_user, {
      raw: I18n.t('election.nominate.desc'),
      topic_id: topic.id
    })
    result = manager.perform

    if result.success?
      {topic_url: topic.url}
    else
      {error_message: "Election creation failed"}
    end
  end

  def self.add_nomination(topic_id, username)
    topic = Topic.find(topic_id)

    nom_string = topic.custom_fields['election_nominations'] || ''
    nominations = nom_string.split('|')
    nominations.push(username)

    update_nominations(topic, nominations)
  end

  def self.remove_nomination(topic_id, username)
    topic = Topic.find(topic_id)

    nom_string = topic.custom_fields['election_nominations'] || ''
    nominations = nom_string.split('|')
    nominations = nominations - [username]

    update_nominations(topic, nominations)
  end

  def self.start_election(topic_id)
    topic = Topic.find(topic_id)
    nom_string = topic.custom_fields['election_nominations'] || ''
    nominations = nom_string.split('|')

    if nominations.length < 2
      return { error_message: I18n.t('election.errors.more_nominations') }
    end

    poll_options = ''

    nominations.each do |n|
      poll_options << "\n- [#{n}](#{Discourse.base_url}/users/#{n})"
    end

    content = "[poll type=regular]#{poll_options}\n[/poll]"

    update_election_post(topic_id, content)

    topic.custom_fields['election_status'] = 'electing'
    topic.election_status_changed = true
    topic.save!

    { success: true }
  end

  def self.category_elections(category_id, opts = {})
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

  def self.update_nominations(topic, nominations)
    content = "#{I18n.t('election.nominate.desc')}"

    if nominations.length > 0
      content << "\n\n#{I18n.t('election.nominate.nominated')}: "

      nominations.each_with_index do |n, i|
        content << "[#{n}](#{Discourse.base_url}/users/#{n})"

        if nominations.size > 1 && i != nominations.size - 1
          content << ", "
        end
      end
    end

    update_election_post(topic.id, content)

    topic.custom_fields['election_nominations'] = nominations.join('|')
    topic.save!

    { success: true }
  end

  def self.update_election_post(topic_id, content)
    election_post = Post.find_by(topic_id: topic_id, post_number: 1)
    revisor = PostRevisor.new(election_post, election_post.topic)
    revisor.revise!(election_post.user, { raw: content }, {})
  end
end
