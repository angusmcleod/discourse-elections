PostRevisor.track_topic_field(:election_nomination_statement)

NewPostManager.add_handler do |manager|
  if SiteSetting.elections_enabled && manager.args[:topic_id]
    topic = Topic.find(manager.args[:topic_id])

    # do nothing if first post in topic
    if topic.subtype === 'election' && topic.try(:highest_post_number) != 0
      extracted_polls = DiscoursePoll::Poll.extract(manager.args[:raw], manager.args[:topic_id], manager.user[:id])

      unless extracted_polls.empty?
        result = NewPostResult.new(:poll, false)
        result.errors[:base] = I18n.t('election.errors.seperate_poll')
        result
      end
    end
  end
end

require_dependency 'post'
class ::Post
  def election_nomination_statement
    if self.custom_fields['election_nomination_statement'] != nil
      self.custom_fields['election_nomination_statement']
    else
      false
    end
  end
end

require_dependency 'post_custom_field'
class ::PostCustomField
  after_save :update_election_status, if: :polls_updated

  def polls_updated
    name == 'polls'
  end

  def update_election_status
    return unless SiteSetting.elections_enabled

    poll = JSON.parse(value)['poll']
    post = Post.find(post_id)
    new_status = nil

    if poll['status'] == 'closed' && post.topic.election_status == Topic.election_statuses[:poll]
      new_status = Topic.election_statuses[:closed_poll]
    end

    if poll['status'] == 'open' && post.topic.election_status == Topic.election_statuses[:closed_poll]
      new_status = Topic.election_statuses[:poll]
    end

    if new_status
      result = DiscourseElections::ElectionTopic.set_status(post.topic_id, new_status)

      if result
        DiscourseElections::ElectionTopic.refresh(post.topic.id)
      end
    end
  end
end

require_dependency 'new_post_manager'
require_dependency 'post_creator'
class DiscourseElections::ElectionPost
  def self.update_poll_status(topic)
    post = topic.first_post
    if post.custom_fields['polls'].present?
      status = topic.election_status == Topic.election_statuses[:closed_poll] ? 'closed' : 'open'
      DiscoursePoll::Poll.toggle_status(post.id, "poll", status, topic.user_id)
    end
  end

  def self.rebuild_election_post(topic, unattended = false)
    topic.reload
    status = topic.election_status

    if status == Topic.election_statuses[:nomination]
      build_nominations(topic, unattended)
    else
      build_poll(topic, unattended)
    end
  end

  private

  def self.build_poll(topic, unattended)
    nominations = topic.election_nominations

    return if nominations.length < 2

    poll_options = ''

    nominations.each do |n|
      # Nominee username is added as a placeholder. Without the username,
      # the 'content' of the token in discourse-markdown/poll is blank
      # which leads to the md5Hash being identical for each option.
      # the username placeholder is removed on the client before render.

      user = User.find(n)
      poll_options << "\n- #{user.username}"
      poll_options << build_nominee(topic, user)
    end

    content = "[poll type=regular]#{poll_options}\n[/poll]"

    message = nil
    if topic.election_status === Topic.election_statuses[:poll]
      message = topic.custom_fields['election_poll_message']
    else
      message = topic.custom_fields['election_closed_poll_message']
    end

    if message
      content << "\n\n #{message}"
    end

    update_election_post(topic, content, unattended)
  end

  def self.build_nominations(topic, unattended)
    content = ""
    nominations = topic.election_nominations

    if nominations.any?
      content << "<div class='title'>#{I18n.t('election.post.nominated')}</div>"

      content << "<div class='nomination-list'>"

      nominations.each do |n|
        user = User.find(n)
        content << build_nominee(topic, user)
      end

      content << "</div>"
    end

    message = topic.custom_fields['election_nomination_message']

    if message.blank?
      message = I18n.t('election.nomination.default_message')
    end

    content << "\n\n #{message}"

    revisor_opts = { skip_validations: true }

    update_election_post(topic, content, unattended, revisor_opts)
  end

  def self.build_nominee(topic, user)
    nomination_statements = topic.election_nomination_statements
    avatar_url = user.avatar_template_url.gsub("{size}", "50")

    html = "<div class='nomination'><span>"

    html << "<div class='nomination-user'>"
    html << "<div class='trigger-user-card' href='/u/#{user.username}' data-user-card='#{user.username}'>"
    html << "<img alt='' width='25' height='25' src='#{avatar_url}' class='avatar'>"
    html << "<a class='mention'>@#{user.username}</a>"
    html << "</div>"
    html << "</div>"

    html << "<div class='nomination-statement'>"
    statement = nomination_statements.find { |s| s['user_id'] == user.id }
    if statement
      post = Post.find(statement['post_id'])
      html << "<a href='#{post.url}'>#{statement['excerpt']}</a>"
    end
    html << "</div>"

    html << "</span></div>"

    html
  end

  def self.update_election_post(topic, content, unattended = false, revisor_opts = {})
    election_post = topic.election_post

    return if !election_post || election_post.raw == content

    revisor = PostRevisor.new(election_post, topic)

    ## We always skip the revision as these are system edits to a single post.
    revisor_opts.merge!(skip_revision: true)

    puts "REVISING: #{content.inspect}"

    revise_result = revisor.revise!(election_post.user, { raw: content }, revisor_opts)

    puts "REVISING RESULT: #{revise_result.inspect}"

    if election_post.errors.any?
      if unattended
        message_moderators(topic.id, election_post.errors.messages.to_s)
      else
        raise ::ActiveRecord::Rollback
      end
    end

    if !revise_result
      if unattended
        message_moderators(topic.id, I18n.t("election.errors.revisor_failed"))
      else
        election_post.errors.add(:base, I18n.t("election.errors.revisor_failed"))
        raise ::ActiveRecord::Rollback
      end
    end

    { success: true }
  end

  def self.message_moderators(topic_id, error)
    DiscourseElections::ElectionTopic.moderators(topic_id).each do |user|
      SystemMessage.create_from_system_user(user,
        :error_updating_election_post,
          topic_id: topic_id,
          error: error
      )
    end
  end
end

DiscourseEvent.on(:post_created) do |post, opts, user|
  if SiteSetting.elections_enabled && opts[:election_nomination_statement] && post.topic.election_nominations.include?(user.id)
    post.custom_fields['election_nomination_statement'] = opts[:election_nomination_statement]
    post.save_custom_fields(true)

    DiscourseElections::NominationStatement.update(post)
  end
end

DiscourseEvent.on(:post_edited) do |post, _topic_changed|
  user = User.find(post.user_id)
  if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
    DiscourseElections::NominationStatement.update(post)
  end
end

DiscourseEvent.on(:post_destroyed) do |post, _opts, user|
  if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
    DiscourseElections::NominationStatement.update(post)
  end
end

DiscourseEvent.on(:post_recovered) do |post, _opts, user|
  if SiteSetting.elections_enabled && post.custom_fields['election_nomination_statement'] && post.topic.election_nominations.include?(user.id)
    DiscourseElections::NominationStatement.update(post)
  end
end
