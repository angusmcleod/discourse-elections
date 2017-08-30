class DiscourseElections::ElectionController < ::ApplicationController
  def create_election
    params.require(:category_id)
    params.require(:position)
    params.permit(:nomination_message, :poll_message, :self_nomination)

    unless current_user.try(:elections_admin?)
      raise StandardError.new I18n.t("election.errors.not_authorized")
    end

    opts = {
      category_id: params[:category_id],
      position: params[:position],
      nomination_message: params[:nomination_message],
      poll_message: params[:poll_message],
      self_nomination_allowed: params[:self_nomination_allowed]
    }

    result = DiscourseElections::ElectionTopic.create(opts)

    if result[:error_message]
      render json: failed_json.merge(message: result[:error_message])
    else
      render json: success_json.merge(topic_url: result[:topic_url])
    end
  end

  def start_election
    params.require(:topic_id)

    unless current_user.try(:elections_admin?)
      raise StandardError.new I18n.t("election.errors.not_authorized")
    end

    topic = Topic.find(params[:topic_id])

    if topic.election_nominations.length < 2
      result = { error_message: I18n.t('election.errors.more_nominations') }
    else
      set_result = DiscourseElections::ElectionTopic.set_status(params[:topic_id], Topic.election_statuses[:poll], current_user.id)
      result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_status_failed') }
    end

    render_result(result)
  end

  def set_nominations
    params.require(:topic_id)
    params.require(:nominations)

    topic = Topic.find(params[:topic_id])
    if topic.election_status != Topic.election_statuses[:nomination] && params[:nominations].length < 2
      result = { error_message: I18n.t('election.errors.more_nominations') }
    else
      DiscourseElections::Nomination.set(params[:topic_id], params[:nominations])
      result = { success: true }
    end

    render_result(result)
  end

  def add_nomination
    params.require(:topic_id)

    DiscourseElections::Nomination.add(params[:topic_id], current_user.id)

    render_result({ success: true })
  end

  def remove_nomination
    params.require(:topic_id)

    DiscourseElections::Nomination.remove(params[:topic_id], current_user.id)

    render_result({ success: true })
  end

  def category_elections
    params.require(:category_id)

    topics = DiscourseElections::ElectionTopic.list_category_elections(params[:category_id])

    render_serialized(topics, DiscourseElections::ElectionSerializer)
  end

  def set_status
    params.require(:topic_id)
    params.require(:status)

    topic = Topic.find(params[:topic_id])

    if params[:status].to_i != Topic.election_statuses[:nomination] && topic.election_nominations.length < 2
      result = { error_message: I18n.t('election.errors.more_nominations') }
    else
      set_result = DiscourseElections::ElectionTopic.set_status(params[:topic_id], params[:status].to_i, current_user.id)
      result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_status_failed') }
    end

    render_result(result)
  end

  def set_self_nomination
    params.require(:topic_id)
    params.require(:selfNomination)

    DiscourseElections::Nomination.set_self_nomination(params[:topic_id], params[:selfNomination])

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
