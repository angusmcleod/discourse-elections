class DiscourseElections::ElectionTime
  def self.set_poll_open_after(topic)
    after_hours = topic.election_poll_open_after_hours
    if topic.election_poll_open && topic.election_poll_open_after && after_hours
      topic.custom_fields['election_poll_open_time'] = (Time.now + after_hours.hours).utc.iso8601
      topic.save_custom_fields(true)

      if after_hours === 0
        Jobs.enqueue(:election_open_poll, topic_id: topic.id)
      else
        self.schedule_poll_open(topic)
      end
    end
  end

  def self.set_poll_close_after(topic)
    after_hours = topic.election_poll_close_after_hours
    if topic.election_poll_close && topic.election_poll_close_after && after_hours != nil
      topic.custom_fields['election_poll_close_time'] = (Time.now + after_hours.hours).utc.iso8601
      topic.save_custom_fields(true)

      if after_hours === 0
        Jobs.enqueue(:election_close_poll, topic_id: topic.id)
      else
        self.schedule_poll_close(topic)
      end
    end
  end

  def self.schedule_poll_open(topic)
    if topic.election_poll_open && topic.election_poll_open_time
      self.cancel_scheduled_poll_open(topic)

      time = Time.parse(topic.election_poll_open_time).utc
      Jobs.enqueue_at(time, :election_open_poll, topic_id: topic.id)

      self.add_time_to_banner(topic, time)

      topic.custom_fields['election_poll_open_scheduled'] = true
      topic.save_custom_fields(true)

      DiscourseElections::ElectionTopic.refresh(topic.id)
    end
  end

  def self.schedule_poll_close(topic)
    if topic.election_poll_close && topic.election_poll_close_time
      self.cancel_scheduled_poll_close(topic)

      time = Time.parse(topic.election_poll_close_time).utc
      Jobs.enqueue_at(time, :election_close_poll, topic_id: topic.id)

      self.add_time_to_banner(topic, time)

      topic.custom_fields['election_poll_close_scheduled'] = true
      topic.save_custom_fields(true)

      DiscourseElections::ElectionTopic.refresh(topic.id)
    end
  end

  def self.add_time_to_banner(topic, time)
    DiscourseElections::ElectionCategory.update_election_list(
      topic.category_id,
      topic.id,
      time: time.to_time.iso8601
    )
  end

  def self.cancel_scheduled_poll_open(topic)
    Jobs.cancel_scheduled_job(:election_open_poll, topic_id: topic.id)

    topic.custom_fields['election_poll_open_scheduled'] = false
    topic.save_custom_fields(true)

    DiscourseElections::ElectionTopic.refresh(topic.id)
  end

  def self.cancel_scheduled_poll_close(topic)
    Jobs.cancel_scheduled_job(:election_close_poll, topic_id: topic.id)

    topic.custom_fields['election_poll_close_scheduled'] = false
    topic.save_custom_fields(true)

    DiscourseElections::ElectionTopic.refresh(topic.id)
  end

  def self.remove_time_from_banner(topic)
    DiscourseElections::ElectionCategory.update_election_list(
      topic.category_id,
      topic.id
    )
  end

  def self.set_poll_open_now(topic)
    if topic.election_poll_open_time.blank?
      topic.custom_fields['election_poll_open_time'] = Time.now.utc.iso8601
      topic.save_custom_fields(true)
    end
  end

  def self.set_poll_close_now(topic)
    if topic.election_poll_close_time.blank?
      topic.custom_fields['election_poll_close_time'] = Time.now.utc.iso8601
      topic.save_custom_fields(true)
    end
  end
end
