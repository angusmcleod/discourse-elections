module Jobs
  class ElectionClosePoll < Jobs::Base
    def execute(args)
      topic = Topic.find(args[:topic_id])

      if SiteSetting.elections_enabled
        if topic && !topic.closed
          error = nil

          if !error && topic.election_status != Topic.election_statuses[:poll]
            error = I18n.t('election.errors.incorrect_status')
          end

          if !error
            new_status = DiscourseElections::ElectionTopic.set_status(topic.id, Topic.election_statuses[:closed_poll])

            if new_status != Topic.election_statuses[:closed_poll]
              error = I18n.t('election.errors.set_status_failed')
            end
          end
        else
          error = I18n.t('election.error.topic_inaccessible')
        end
      else
        error = I18n.t('election.error.elections_disabled')
      end

      if error
        SystemMessage.create_from_system_user(Discourse.site_contact_user,
          :error_closing_poll,
            topic_id: args[:topic_id],
            error: error
        )
      end
    end
  end
end
