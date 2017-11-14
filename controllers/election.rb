module DiscourseElections
  class ElectionController < BaseController
    before_action :ensure_is_elections_admin
    before_action :ensure_is_elections_category, only: [:create]

    def create
      params.require(:category_id)
      params.require(:position)
      params.permit(:nomination_message, :poll_message, :self_nomination_allowed, :status_banner, :status_banner_result_hours)

      opts = {
        category_id: params[:category_id],
        position: params[:position],
        nomination_message: params[:nomination_message],
        poll_message: params[:poll_message],
        self_nomination_allowed: params[:self_nomination_allowed],
        status_banner: params[:status_banner],
        status_banner_result_hours: params[:status_banner_result_hours]
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
        raise StandardError.new I18n.t('election.errors.not_changed')
      end

      if params[:status].to_i != Topic.election_statuses[:nomination] && topic.election_nominations.length < 2
        raise StandardError.new I18n.t('election.errors.more_nominations')
      end

      new_status = DiscourseElections::ElectionTopic.set_status(params[:topic_id], params[:status].to_i)

      if new_status == existing_status
        result = { error_message: I18n.t('election.errors.set_status_failed') }
      else
        result = { value: new_status }
        election_post = Post.find_by(topic_id: params[:topic_id], post_number: 1)
        poll_status = params[:status].to_i == Topic.election_statuses[:closed_poll] ? 'closed' : 'open'
        DiscoursePoll::Poll.toggle_status(election_post.id, "poll", poll_status, current_user.id)
      end

      render_result(result)
    end

    def set_status_banner
      params.require(:topic_id)
      params.require(:status_banner)

      topic = Topic.find(params[:topic_id])
      existing_state = topic.custom_fields['election_status_banner']

      if params[:status_banner].to_s == existing_state.to_s
        raise StandardError.new I18n.t('election.errors.not_changed')
      end

      topic.custom_fields['election_status_banner'] = params[:status_banner]
      topic.save_custom_fields(true)

      DiscourseElections::ElectionCategory.update_election_list(topic.category_id, topic.id, banner: params[:status_banner])

      render_result(value: topic.custom_fields['election_status_banner'])
    end

    def set_status_banner_result_hours
      params.require(:topic_id)
      params.require(:status_banner_result_hours)

      topic = Topic.find(params[:topic_id])
      existing = topic.custom_fields['election_status_banner_result_hours']

      if params[:status_banner_result_hours].to_i == existing.to_i
        raise StandardError.new I18n.t('election.errors.not_changed')
      end

      topic.custom_fields['election_status_banner_result_hours'] = params[:status_banner_result_hours]
      topic.save_custom_fields(true)

      render_result(value: topic.custom_fields['election_status_banner_result_hours'])
    end

    def set_self_nomination_allowed
      params.require(:topic_id)
      params.require(:self_nomination_allowed)

      topic = Topic.find(params[:topic_id])
      existing_state = topic.custom_fields['election_self_nomination_allowed']

      if params[:self_nomination_allowed].to_s == existing_state.to_s
        raise StandardError.new I18n.t('election.errors.self_nomination_state_not_changed')
      end

      response = DiscourseElections::Nomination.set_self_nomination(params[:topic_id], params[:self_nomination_allowed])

      if response == existing_state
        result = { error_message: I18n.t('election.errors.self_nomination_state_not_changed') }
      else
        result = { value: response }
      end

      render_result(result)
    end

    def set_message
      params.require(:topic_id)
      params.permit(:poll_message, :nomination_message)

      type = nil
      message = nil

      params.each do |key|
        if key.to_s.include? 'message'
          message = params[key]
          type = key.split('_')[0]
        end
      end

      if type && message && success = DiscourseElections::ElectionTopic.set_message(
          params[:topic_id],
          params[:message],
          params[:type]
        )
        result = { value: params[:message] }
      else
        result = { error_message: I18n.t('election.errors.set_message_failed') }
      end

      render_result(result)
    end

    def set_position
      params.require(:topic_id)
      params.require(:position)

      if params[:position].length < 3
        raise StandardError.new I18n.t('election.errors.position_too_short')
      end

      if success = DiscourseElections::ElectionTopic.set_position(params[:topic_id], params[:position])
        result = { value: params[:position] }
      else
        result = { error_message: I18n.t('election.errors.set_position_failed') }
      end

      render_result(result)
    end
  end
end
