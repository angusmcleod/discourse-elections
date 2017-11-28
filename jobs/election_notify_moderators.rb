module Jobs
  class ElectionNotifyModerators < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])
      key = "election.notification.#{args[:type]}"

      site_moderators.each do |user|
        if user
          user.notifications.create(notification_type: Notification.types[:custom],
                                    topic_id: args[:topic_id],
                                    data: { message: key,
                                            description: I18n.t(key, title: topic.title) }.to_json)
        end
      end
    end

    def site_moderators
      all = User.where(moderator: true).human_users.pluck(:username)
      all.select { |u| u.custom_fields['moderator_category_id'].blank? }
    end
  end
end
