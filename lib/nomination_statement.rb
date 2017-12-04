class DiscourseElections::NominationStatement

  def self.update(post, rebuild_post = true)
    statements = post.topic.election_nomination_statements
    existing = false
    excerpt = PrettyText.excerpt(post.cooked, 100, keep_emoji_images: true)

    statements.each do |s|
      if s['post_id'] == post.id
        existing = true
        s['excerpt'] = excerpt
      end
    end

    unless existing
      statements.push(
        post_id: post.id,
        user_id: post.user.id,
        excerpt: excerpt
      )
    end

    if rebuild_post
      save_and_rebuild(post.topic, statements)
    else
      save(post.topic, statements)
    end
  end

  def self.remove(topic, removed_nominations, rebuild_post = true)
    statements = topic.election_nomination_statements

    removed_statements = []

    removed_nominations.each do |rn|
      statements = statements.reject do |s|
        if s['user_id'] == rn
          removed_statements.push(s)
          true
        end
      end
    end

    if rebuild_post
      save_and_rebuild(topic, statements)
    else
      save(topic, statements)
    end
  end

  def self.save(topic, statements)
    topic.custom_fields['election_nomination_statements'] = JSON.generate(statements)
    topic.save_custom_fields(true)
  end

  def self.save_and_rebuild(topic, statements)
    TopicCustomField.transaction do
      self.save(topic, statements)
      DiscourseElections::ElectionPost.rebuild_election_post(topic)
    end

    update_posts(statements)
  end

  def self.update_posts(statements)
    statements.each do |s|
      s = s.with_indifferent_access
      if s[:post_id]
        post = Post.find(s['post_id'])
        post.publish_change_to_clients!(:revised)
      end
    end
  end

  def self.retrieve(topic_id, nominees)
    existing_statements = []

    nominees.each do |u|
      user = User.find(u)
      user_posts = Post.where(user_id: user.id, topic_id: topic_id)

      if user_posts.any?
        user_statement = user_posts.joins("INNER JOIN post_custom_fields
                                           ON post_custom_fields.post_id = posts.id
                                           AND post_custom_fields.name = 'election_nomination_statement'
                                           AND post_custom_fields.value = 'true'").first
        if user_statement
          existing_statements.push(user_statement)
        end
      end
    end

    existing_statements
  end
end
