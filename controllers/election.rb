module DiscourseElections
  class ElectionController < BaseController
    before_action :ensure_is_elections_admin
    before_action :ensure_is_elections_category, only: [:create]

    def create
      params.require(:category_id)
      params.require(:position)
      params.permit(:nomination_message,
                    :poll_message,
                    :closed_poll_message,
                    :self_nomination_allowed,
                    :status_banner,
                    :status_banner_result_hours,
                    :poll_open,
                    :poll_open_after,
                    :poll_open_after_hours,
                    :poll_open_after_nominations,
                    :poll_open_time,
                    :poll_close,
                    :poll_close_after,
                    :poll_close_after_hours,
                    :poll_close_time)

      validate_create_time('open') if params[:poll_open]
      validate_create_time('close') if params[:poll_close]

      result = DiscourseElections::ElectionTopic.create(current_user, params)

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
      status = params[:status].to_i
      existing_status = topic.election_status

      if status == existing_status
        raise StandardError.new I18n.t('election.errors.not_changed')
      end

      if status != Topic.election_statuses[:nomination] && topic.election_nominations.length < 2
        raise StandardError.new I18n.t('election.errors.more_nominations')
      end

      new_status = DiscourseElections::ElectionTopic.set_status(params[:topic_id], status)

      if new_status == existing_status
        result = { error_message: I18n.t('election.errors.set_status_failed') }
      else
        result = { value: new_status }
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
      params.permit(:nomination_message, :poll_message, :closed_poll_message)

      type = nil
      message = nil

      params.each do |key|
        if key && key.to_s.include?('message')
          message = params[key]
          parts = key.split('_')
          parts.pop
          type = parts.join('_')
        end
      end

      if type && message && success = DiscourseElections::ElectionTopic.set_message(
          params[:topic_id],
          message,
          type
        )
        result = { value: message }
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

    def set_poll_time
      params.require(:topic_id)
      params.require(:type)
      params.require(:enabled)
      params.permit(:after, :hours, :nominations, :time)

      enabled = params[:enabled] === 'true'
      after = params[:after] === 'true'
      hours = params[:hours].to_i
      nominations = params[:nominations].to_i
      time = params[:time]
      type = params[:type]

      if enabled
        validate_time(
          type: type,
          after: after,
          hours: hours,
          nominations: nominations,
          time: time
        )
      end

      topic = Topic.find(params[:topic_id])
      nominations_count = topic.election_nominations.length

      if type === 'open' && enabled && after && nominations_count >= nominations
        raise StandardError.new I18n.t('election.errors.nominations_already_met')
      end

      enabled_str = "election_poll_#{type}"
      after_str = "election_poll_#{type}_after"
      hours_str = "election_poll_#{type}_after_hours"
      nominations_str = "election_poll_#{type}_after_nominations"
      time_str = "election_poll_#{type}_time"

      topic.custom_fields[enabled_str] = enabled if enabled != topic.send(enabled_str)
      topic.custom_fields[after_str] = after if after != topic.send(after_str)

      if after
        topic.custom_fields[hours_str] = hours if hours != topic.send(hours_str)
        if type === 'open' && nominations != topic.send(nominations_str)
          topic.custom_fields[nominations_str] = nominations
        end
      else
        topic.custom_fields[time_str] = time if time != topic.send(time_str)
      end

      if saved = topic.save_custom_fields(true)
        if topic.send(enabled_str)
          if (topic.send(after_str))
            if topic.election_nominations.length >= topic.election_poll_open_after_nominations
              DiscourseElections::ElectionTime.send("set_poll_#{type}_after", topic)
            else
              DiscourseElections::ElectionTime.send("cancel_scheduled_poll_#{type}", topic)
            end
          else
            DiscourseElections::ElectionTime.send("schedule_poll_#{type}", topic)
          end
        else
          DiscourseElections::ElectionTime.send("cancel_scheduled_poll_#{type}", topic)
        end
      end

      if saved
        result = {}
      else
        result = { error_message: I18n.t('election.errors.set_poll_time_failed') }
      end

      render_result(result)
    end

    private

    def validate_create_time(type)
      validate_time(
        type: type,
        after: params["poll_#{type}_after".to_sym] == 'true',
        hours: params["poll_#{type}_after_hours".to_sym].to_i,
        nominations: params["poll_#{type}_after_nominations".to_sym].to_i,
        time: params["poll_#{type}_time".to_sym]
      )
    end

    def validate_time(opts)
      if opts[:after]
        if opts[:hours].blank? || (opts[:type] === 'open' && opts[:nominations].blank?)
          raise StandardError.new I18n.t('election.errors.poll_after')
        elsif opts[:type] === 'open' && opts[:nominations].to_i < 2
          raise StandardError.new I18n.t('election.errors.nominations_at_least_2')
        elsif opts[:type] === 'close' && opts[:hours].to_i < 1
          raise StandardError.new I18n.t('election.errors.close_hours_at_least_1')
        end
      elsif opts[:time].blank?
        raise StandardError.new I18n.t('election.errors.poll_manual')
      else
        begin
          time = Time.parse(opts[:time]).utc
          if time < Time.now.utc
            raise StandardError.new I18n.t('election.errors.time_invalid')
          end
        rescue ArgumentError
          raise StandardError.new I18n.t('election.errors.time_invalid')
        end
      end
    end
  end
end
