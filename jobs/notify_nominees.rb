module Jobs
  class NotifyNominees < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])

      topic.election_nominations.each do |user_id|
        user = User.find(user_id)

        if user
          user.notifications.create(notification_type: Notification.types[:custom],
                                    data: { topic_id: args[:topic_id],
                                            message: "election.nomination.notification",
                                            description: args[:message] }.to_json)
        end
      end
    end
  end
end
