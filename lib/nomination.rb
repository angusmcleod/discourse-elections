class DiscourseElections::Nomination

  def self.set_by_username(topic_id, usernames)
    topic = Topic.find(topic_id)
    existing_nominations = topic.election_nominations

    nominations = []
    usernames.each do |u|
      user = User.find_by(username: u)
      nominations.push(user.id)
    end

    return if Set.new(existing_nominations) == Set.new(nominations)

    self.save(topic, nominations)

    removed_nominations = existing_nominations.reject{ |n| !n || nominations.include?(n) }

    if removed_nominations.any?
      DiscourseElections::NominationStatement.remove(topic, removed_nominations)
    end

    added_nominations = nominations.reject{ |u| !u || existing_nominations.include?(u) }

    if added_nominations.any?
      self.handle_new(topic, added_nominations)
    end
  end

  def self.add(topic_id, user_id)
    topic = Topic.find(topic_id)

    nominations = topic.election_nominations
    nominations.push(user_id) unless nominations.include?(user_id)

    self.save(topic, nominations)
    self.handle_new(topic, [user_id])
  end

  def self.remove(topic_id, user_id)
    topic = Topic.find(topic_id)

    nominations = topic.election_nominations - [user_id]

    self.save(topic, nominations)

    DiscourseElections::NominationStatement.remove(topic, [user_id])
    DiscourseElections::ElectionPost.rebuild_election_post(topic)
  end

  def self.save(topic, nominations)
    topic.custom_fields['election_nominations'] = nominations.length < 2 ? nominations[0] : nominations
    topic.save!
  end

  def self.handle_new(topic, new_nominations)
    existing_statements = DiscourseElections::NominationStatement.retrieve(topic.id, new_nominations)

    if existing_statements.any?
      existing_statements.each do |statement|
        DiscourseElections::NominationStatement.update(statement)
      end
    else
      DiscourseElections::ElectionPost.rebuild_election_post(topic)
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
