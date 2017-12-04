module DiscourseElections
  class NominationController < BaseController
    before_action :ensure_logged_in
    before_action :ensure_is_elections_admin, only: [:set_by_username]

    def set_by_username
      params.require(:topic_id)

      usernames = params[:usernames].blank? ? [] : [*params[:usernames]]

      topic = Topic.find(params[:topic_id])
      if topic.election_status != Topic.election_statuses[:nomination] && usernames.length < 2
        raise StandardError.new I18n.t('election.errors.more_nominations')
      end

      result = DiscourseElections::Nomination.set_by_username(params[:topic_id], usernames)

      render_result(result)
    end

    def add
      params.require(:topic_id)

      user = current_user
      min_trust = SiteSetting.elections_min_trust_to_self_nominate.to_i

      if !user || user.anonymous?
        result = { error_message: I18n.t('election.errors.only_named_user_can_self_nominate') }
      elsif user.trust_level < min_trust
        result = { error_message: I18n.t('election.errors.insufficient_trust_to_self_nominate', level: min_trust) }
      else
        DiscourseElections::Nomination.add_user(params[:topic_id], user.id)
        result = { success: true }
      end

      render_result(result)
    end

    def remove
      params.require(:topic_id)

      DiscourseElections::Nomination.remove_user(params[:topic_id], current_user.id)

      render_result
    end
  end
end
