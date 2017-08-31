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
      set_result = DiscourseElections::ElectionTopic.set_status(params[:topic_id], Topic.election_statuses[:poll])
      result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_status_failed') }
    end

    render_result(result)
  end

  def set_nominations_by_username
    params.require(:topic_id)
    params.require(:usernames)

    topic = Topic.find(params[:topic_id])
    if topic.election_status != Topic.election_statuses[:nomination] && params[:usernames].length < 2
      result = { error_message: I18n.t('election.errors.more_nominations') }
    else
      DiscourseElections::Nomination.set_by_username(params[:topic_id], params[:usernames])
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
      set_result = DiscourseElections::ElectionTopic.set_status(params[:topic_id], params[:status].to_i)

      if set_result
        election_post = Post.find_by(topic_id: params[:topic_id], post_number: 1)
        poll_status = params[:status].to_i == Topic.election_statuses[:closed_poll] ? 'closed' : 'open'

        DiscoursePoll::Poll.toggle_status(election_post.id, "poll", poll_status, current_user.id)

        result = { success: true }
      else
        result = { error_message: I18n.t('election.errors.set_status_failed') }
      end
    end

    render_result(result)
  end

  def set_self_nomination
    params.require(:topic_id)
    params.require(:self_nomination)

    DiscourseElections::Nomination.set_self_nomination(params[:topic_id], params[:self_nomination])

    render_result({ success: true })
  end

  def set_nomination_message
    params.require(:topic_id)
    params.permit(:nomination_message, nomination_message: '')

    set_result = DiscourseElections::ElectionTopic.set_message(params[:topic_id], params[:nomination_message], 'nomination')

    result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_message_failed')}

    render_result(result)
  end

  def set_poll_message
    params.require(:topic_id)
    params.permit(:poll_message, poll_message: '')

    set_result = DiscourseElections::ElectionTopic.set_message(params[:topic_id], params[:poll_message], 'poll')

    result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_message_failed')}

    render_result(result)
  end

  def set_position
    params.require(:topic_id)
    params.require(:position)

    if params[:position].length < 3
      result = { error_message: I18n.t('election.errors.position_too_short') }
    else
      set_result = DiscourseElections::ElectionTopic.set_position(params[:topic_id], params[:position])
      result = set_result ? { success: true } : { error_message: I18n.t('election.errors.set_position_failed')}
    end

    render_result(result)
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
