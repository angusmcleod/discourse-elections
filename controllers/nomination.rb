module DiscourseElections
  class NominationController < BaseController
    before_filter :ensure_is_elections_admin, only: [:set_by_username]

    def set_by_username
      params.require(:topic_id)
      params.permit(:usernames, usernames: '', usernames: [])

      usernames = params[:usernames].empty? ? [] : [*params[:usernames]]

      topic = Topic.find(params[:topic_id])
      if topic.election_status != Topic.election_statuses[:nomination] && usernames.length < 2
        raise StandardError.new I18n.t('election.errors.more_nominations')
      end

      result = DiscourseElections::Nomination.set_by_username(params[:topic_id], usernames)

      render_result(result)
    end

    def add
      params.require(:topic_id)

      DiscourseElections::Nomination.add(params[:topic_id], current_user.id)

      render_result
    end

    def remove
      params.require(:topic_id)

      DiscourseElections::Nomination.remove(params[:topic_id], current_user.id)

      render_result
    end
  end
end
