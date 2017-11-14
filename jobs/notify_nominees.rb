module Jobs
  class NotifyNominees < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])
      key = "election.notification.#{args[:type]}"

      topic.election_nominations.each do |user_id|
        user = User.find(user_id)

        if user
          user.notifications.create(notification_type: Notification.types[:custom],
                                    topic_id: args[:topic_id],
                                    data: { message: key,
                                            description: I18n.t(key, title: topic.title) }.to_json)
        end
      end
    end
  end
end
