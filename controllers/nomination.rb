class DiscourseElections::NominationController < ::ApplicationController
  before_filter :ensure_is_elections_admin, only: [:set_by_username]

  def set_by_username
    params.require(:topic_id)
    params.require(:usernames)

    topic = Topic.find(params[:topic_id])
    if topic.election_status != Topic.election_statuses[:nomination] && params[:usernames].length < 2
      raise StandardError.new I18n.t('election.errors.more_nominations')
    end

    DiscourseElections::Nomination.set_by_username(params[:topic_id], params[:usernames])
    result = { success: true }

    render_result(result)
  end

  def add
    params.require(:topic_id)

    DiscourseElections::Nomination.add(params[:topic_id], current_user.id)

    render_result({ success: true })
  end

  def remove
    params.require(:topic_id)

    DiscourseElections::Nomination.remove(params[:topic_id], current_user.id)

    render_result({ success: true })
  end

  private

  def render_result(result = {})
    if result[:error_message]
      render json: failed_json.merge(message: result[:error_message])
    else
      render json: success_json
    end
  end
end
