class DiscourseElections::Nomination

  def self.set(topic_id, usernames)
    topic = Topic.find(topic_id)
    nominations = usernames
    existing_nominations = topic.election_nominations

    return if Set.new(existing_nominations) == Set.new(usernames)

    self.save(topic, nominations)

    removed_nominations = existing_nominations.reject{ |n| n.empty? || nominations.include?(n) }

    if removed_nominations.any?
      DiscourseElections::NominationStatement.remove(topic, removed_nominations)
    end

    added_nominations = usernames.reject{ |u| u.empty? || existing_nominations.include?(u) }

    if added_nominations.any?
      self.handle_new(topic, added_nominations)
    end

    { success: true }
  end

  def self.add(topic_id, username)
    topic = Topic.find(topic_id)
    nominations = topic.election_nominations
    nominations.push(username) unless nominations.include?(username)

    self.save(topic, nominations)

    self.handle_new(topic, [username])

    { success: true }
  end

  def self.remove(topic_id, username)
    topic = Topic.find(topic_id)

    self.save(topic, topic.election_nominations - [username])

    DiscourseElections::NominationStatement.remove(topic, [username])

    DiscourseElections::ElectionPost.build_nominations(topic)

    { success: true }
  end

  def self.save(topic, nominations)
    topic.custom_fields['election_nominations'] = nominations.join('|')
    topic.save!
  end

  def self.handle_new(topic, new_nominations)
    existing_statements = DiscourseElections::NominationStatement.retrieve(topic.id, new_nominations)

    if existing_statements.any?
      existing_statements.each do |statement|
        DiscourseElections::NominationStatement.update(statement)
      end
    else
      DiscourseElections::ElectionPost.build_nominations(topic)
    end
  end

  def self.set_self_nomination(topic_id, state)
    topic = Topic.find(topic_id)
    topic.custom_fields['election_self_nomination_allowed'] = state
    result = topic.save!

    MessageBus.publish("/topic/#{topic_id}", reload_topic: true)

    { success: result }
  end
end
