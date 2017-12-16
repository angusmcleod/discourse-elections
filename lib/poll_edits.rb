require_dependency Rails.root.join('plugins', 'poll', 'lib', 'polls_updater').to_s

DiscoursePoll::PollsUpdater.class_eval do
  def self.update(post, polls)
    # load previous polls
    previous_polls = post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD] || {}

    # extract options
    current_option_ids = extract_option_ids(polls)
    previous_option_ids = extract_option_ids(previous_polls)

    # are the polls different?
    if polls_updated?(polls, previous_polls) || (current_option_ids != previous_option_ids)
      has_votes = total_votes(previous_polls) > 0

      # outside of the edit window?
      poll_edit_window_mins = SiteSetting.poll_edit_window_mins
      open_time = post.topic.election_poll_open_time || post.updated_at

      if open_time < poll_edit_window_mins.minutes.ago && has_votes
        # cannot add/remove/rename polls
        if polls.keys.sort != previous_polls.keys.sort
          post.errors.add(:base, I18n.t(
            "poll.edit_window_expired.cannot_change_polls", minutes: poll_edit_window_mins
          ))

          return
        end

        # deal with option changes
        if User.staff.pluck(:id).include?(post.last_editor_id)
          # staff can only edit options
          polls.each_key do |poll_name|
            if polls[poll_name]["options"].size != previous_polls[poll_name]["options"].size && previous_polls[poll_name]["voters"].to_i > 0
              post.errors.add(:base, I18n.t(
                "poll.edit_window_expired.staff_cannot_add_or_remove_options",
                minutes: poll_edit_window_mins
              ))

              return
            end
          end
        else
          # OP cannot edit poll options
          post.errors.add(:base, I18n.t(
            "poll.edit_window_expired.op_cannot_edit_options",
            minutes: poll_edit_window_mins
          ))

          return
        end
      end

      # try to merge votes
      polls.each_key do |poll_name|
        next unless previous_polls.has_key?(poll_name)
        return if has_votes && private_to_public_poll?(post, previous_polls, polls, poll_name)

        # when the # of options has changed, reset all the votes
        if polls[poll_name]["options"].size != previous_polls[poll_name]["options"].size
          PostCustomField.where(post_id: post.id, name: DiscoursePoll::VOTES_CUSTOM_FIELD).destroy_all
          post.clear_custom_fields
          next
        end

        polls[poll_name]["voters"] = previous_polls[poll_name]["voters"]

        if previous_polls[poll_name].has_key?("anonymous_voters")
          polls[poll_name]["anonymous_voters"] = previous_polls[poll_name]["anonymous_voters"]
        end

        previous_options = previous_polls[poll_name]["options"]
        public_poll = polls[poll_name]["public"] == "true"

        polls[poll_name]["options"].each_with_index do |option, index|
          previous_option = previous_options[index]
          option["votes"] = previous_option["votes"]

          if previous_option["id"] != option["id"]
            if votes_fields = post.custom_fields[DiscoursePoll::VOTES_CUSTOM_FIELD]
              votes_fields.each do |key, value|
                next unless value[poll_name]
                index = value[poll_name].index(previous_option["id"])
                votes_fields[key][poll_name][index] = option["id"] if index
              end
            end
          end

          if previous_option.has_key?("anonymous_votes")
            option["anonymous_votes"] = previous_option["anonymous_votes"]
          end

          if public_poll && previous_option.has_key?("voter_ids")
            option["voter_ids"] = previous_option["voter_ids"]
          end
        end
      end

      # immediately store the polls
      post.custom_fields[DiscoursePoll::POLLS_CUSTOM_FIELD] = polls
      post.save_custom_fields(true)

      # publish the changes
      MessageBus.publish("/polls/#{post.topic_id}", post_id: post.id, polls: polls)
    end
  end
end

module PollElectionsExtension
  def vote(post_id, poll_name, options, user)
    result = super
    post = Post.find(post_id)
    if post.topic.election && post.topic.election_poll_voters >= post.topic.election_poll_close_after_voters
      DiscourseElections::ElectionTime.set_poll_close_after(post.topic)
    end
    result
  end
end

class DiscoursePoll::Poll
  class << self
    prepend PollElectionsExtension
  end
end
