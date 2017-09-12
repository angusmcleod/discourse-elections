class DiscourseElections::Nomination

  def self.set_by_username(topic_id, usernames)
    topic = Topic.find(topic_id)
    existing_nominations = topic.election_nominations

    nominations = []

    if usernames.any?
      usernames.each do |u|
        unless u.empty?
          user = User.find_by(username: u)
          if user
            nominations.push(user.id)
          else
            raise StandardError.new I18n.t('election.errors.user_was_not_found', user: u)
          end
        end
      end
    end

    return if Set.new(existing_nominations) == Set.new(nominations)

    unless self.save(topic, nominations)
      raise StandardError.new I18n.t('election.errors.set_usernames_failed')
    end

    removed_nominations = existing_nominations.reject { |n| !n || nominations.include?(n) }

    if removed_nominations.any?
      self.remove(topic.id, removed_nominations)
    end

    added_nominations = nominations.reject { |u| !u || existing_nominations.include?(u) }

    if added_nominations.any?
      self.handle_new(topic, added_nominations)
    end

    { usernames: usernames, user_ids: nominations }
  end

  def self.add(topic_id, user_id)
    topic = Topic.find(topic_id)

    nominations = topic.election_nominations
    nominations.push(user_id) unless nominations.include?(user_id)

    if self.save(topic, nominations)
      self.handle_new(topic, [user_id])
    else
      return raise StandardError.new I18n.t('election.errors.add_nominee_failed')
    end
  end

  def self.remove(topic_id, removed_nominations)
    topic = Topic.find(topic_id)

    removed_nominations = [*removed_nominations]

    nominations = topic.election_nominations - removed_nominations

    if self.save(topic, nominations)
      topic.reload.election_nominations

      if topic.election_nomination_statements.reject { |n| !removed_nominations.include?(n['user_id']) }.any?
        DiscourseElections::NominationStatement.remove(topic, removed_nominations)
      end

      DiscourseElections::ElectionPost.rebuild_election_post(topic)
    else
      return raise StandardError.new I18n.t('election.errors.remove_nominee_failed')
    end
  end

  def self.save(topic, nominations)
    topic.custom_fields['election_nominations'] = [*nominations]
    result = topic.save!
    result
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

    topic.custom_fields['election_self_nomination_allowed']
  end
end
