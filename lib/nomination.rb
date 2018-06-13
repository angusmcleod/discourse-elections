module DiscourseElections
  class Nomination

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

      if Set.new(existing_nominations) == Set.new(nominations)
        raise StandardError.new I18n.t('election.errors.nominations_not_changed')
      end

      saved = false
      TopicCustomField.transaction do
        if saved = Nomination.save(topic, nominations)
          removed_nominations = existing_nominations.reject { |n| !n || nominations.include?(n) }
          added_nominations = nominations.reject { |u| !u || existing_nominations.include?(u) }

          if added_nominations.any?
            Nomination.handle_new(topic, added_nominations)
          end

          if removed_nominations.any?
            Nomination.handle_remove(topic, removed_nominations)
          end
        end
      end

      if !saved || topic.election_post.errors.any?
        raise StandardError.new I18n.t('election.errors.set_nominations_failed')
      end

      { usernames: usernames, user_ids: nominations }
    end

    def self.add_user(topic_id, user_id)
      topic = Topic.find(topic_id)
      nominations = topic.election_nominations

      if !nominations.include?(user_id)
        nominations.push(user_id)
      end

      saved = false
      TopicCustomField.transaction do
        if saved = Nomination.save(topic, nominations)
          Nomination.handle_new(topic, [user_id])
        end
      end

      if !saved || topic.election_post.errors.any?
        raise StandardError.new I18n.t('election.errors.set_nominations_failed')
      end

      topic.election_nominations
    end

    def self.remove_user(topic_id, user_id)
      topic = Topic.find(topic_id)
      nominations = topic.election_nominations

      if nominations.include?(user_id)
        nominations = topic.election_nominations - removed_nominations
      end

      saved = false
      TopicCustomField.transaction do
        if saved = Nomination.save(topic, nominations)
          Nomination.handle_remove(topic, [user_id])
        end
      end

      if !saved || topic.election_post.errors.any?
        raise StandardError.new I18n.t('election.errors.set_nominations_failed')
      end

      topic.election_nominations
    end

    def self.save(topic, nominations)
      topic.custom_fields['election_nominations'] = [*nominations]
      topic.save_custom_fields(true)
    end

    def self.handle_new(topic, new_nominations)
      existing_statements = NominationStatement.retrieve(topic.id, new_nominations)

      if existing_statements.any?
        existing_statements.each do |statement|
          NominationStatement.update(statement, false)
        end
      end

      ElectionPost.rebuild_election_post(topic)

      if topic.election_nominations.length >= topic.election_poll_open_after_nominations
        ElectionTime.set_poll_open_after(topic)
      end
    end

    def self.handle_remove(topic, removed_nominations)
      topic.reload.election_nominations

      NominationStatement.remove(topic, removed_nominations, false)

      ElectionPost.rebuild_election_post(topic)

      if topic.election_nominations.length < topic.election_poll_open_after_nominations
        ElectionTime.cancel_scheduled_poll_open(topic)
      end
    end

    def self.set_self_nomination(topic_id, state)
      topic = Topic.find(topic_id)
      topic.custom_fields['election_self_nomination_allowed'] = state
      result = topic.save!

      ElectionTopic.refresh(topic_id)

      topic.custom_fields['election_self_nomination_allowed']
    end

    def self.notify_nominees(topic_id, type)
      Jobs.cancel_scheduled_job(:election_notify_nominees, topic_id: topic_id, type: 'poll')
      Jobs.cancel_scheduled_job(:election_notify_nominees, topic_id: topic_id, type: 'closed_poll')
      Jobs.enqueue_in(1.hour, :election_notify_nominees, topic_id: topic_id, type: type)
    end
  end
end
