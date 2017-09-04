class DiscourseElections::ElectionController < ::ApplicationController
  before_filter :ensure_is_elections_admin
  before_filter :ensure_is_elections_category, only: [:create]

  def create
    params.require(:category_id)
    params.require(:position)
    params.permit(:nomination_message, :poll_message, :self_nomination_allowed)

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
      render json: success_json.merge(url: result[:url])
    end
  end

  def start_poll
    params.require(:topic_id)

    topic = Topic.find(params[:topic_id])

    if topic.election_nominations.length < 2
      raise StandardError.new I18n.t('election.errors.more_nominations')
    end

    new_status = DiscourseElections::ElectionTopic.set_status(params[:topic_id], Topic.election_statuses[:poll])

    if new_status != Topic.election_statuses[:poll]
      result = { error_message: I18n.t('election.errors.set_status_failed') }
    else
      result = { status: new_status }
    end

    render_result(result)
  end

  def set_status
    params.require(:topic_id)
    params.require(:status)

    topic = Topic.find(params[:topic_id])
    existing_status = topic.election_status

    if params[:status].to_i == existing_status
      raise StandardError.new I18n.t('election.errors.status_not_changed')
    end

    if params[:status].to_i != Topic.election_statuses[:nomination] && topic.election_nominations.length < 2
      raise StandardError.new I18n.t('election.errors.more_nominations')
    end

    new_status = DiscourseElections::ElectionTopic.set_status(params[:topic_id], params[:status].to_i)

    if new_status == existing_status
      result = { error_message: I18n.t('election.errors.set_status_failed') }
    else
      result = { status: new_status }
      election_post = Post.find_by(topic_id: params[:topic_id], post_number: 1)
      poll_status = params[:status].to_i == Topic.election_statuses[:closed_poll] ? 'closed' : 'open'
      DiscoursePoll::Poll.toggle_status(election_post.id, "poll", poll_status, current_user.id)
    end

    render_result(result)
  end

  def set_self_nomination
    params.require(:topic_id)
    params.require(:state)

    topic = Topic.find(params[:topic_id])
    existing_state = topic.custom_fields['election_self_nomination_allowed']

    if params[:state] == existing_state
      raise StandardError.new I18n.t('election.errors.self_nomination_state_not_changed')
    end

    response = DiscourseElections::Nomination.set_self_nomination(params[:topic_id], params[:state])

    if response == existing_state
      result = { error_message: I18n.t('election.errors.self_nomination_state_not_changed') }
    else
      result = { state: response }
    end

    render_result(result)
  end

  def set_message
    params.require(:topic_id)
    params.require(:type)
    params.permit(:message, message: '')

    unless params.has_key?(:message)
      raise ActionController::ParameterMissing.new(:message)
    end

    response = DiscourseElections::ElectionTopic.set_message(params[:topic_id], params[:message], params[:type])
    result = response ? {} : {error_message: I18n.t('election.errors.set_message_failed')}

    render_result(result)
  end

  def set_position
    params.require(:topic_id)
    params.require(:position)

    if params[:position].length < 3
      raise StandardError.new I18n.t('election.errors.position_too_short')
    end

    response = DiscourseElections::ElectionTopic.set_position(params[:topic_id], params[:position])

    result = response ? {} : {error_message: I18n.t('election.errors.set_position_failed')}

    render_result(result)
  end

  private

  def render_result(result = {})
    if result[:error_message]
      render json: failed_json.merge(message: result[:error_message])
    else
      render json: success_json.merge(result)
    end
  end
end
