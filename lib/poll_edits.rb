require_dependency Rails.root.join('plugins', 'poll', 'lib', 'polls_updater').to_s

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
