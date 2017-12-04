module Jobs
  class ElectionNotifyModerators < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])
      status = I18n.t("election.status.#{args[:type]}", title: topic.title)

      DiscourseElections::ElectionTopic.moderators(topic.id).each do |user|
        if user
          SystemMessage.create_from_system_user(user,
            :election_status_changed,
              status: status,
              title: topic.title,
              url: topic.url
          )
        end
      end
    end
  end
end
