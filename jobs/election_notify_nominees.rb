module Jobs
  class ElectionNotifyNominees < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])
      status = I18n.t("election.status.#{args[:type]}", title: topic.title)

      topic.election_nominations.each do |user_id|
        user = User.find(user_id)

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
