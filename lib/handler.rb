require_dependency 'new_post_manager'
require_dependency 'post_creator'

class DiscourseElections::Handler
  def self.create_election_topic(category_id, position, details_url, message, self_nomination_allowed)
    category = Category.find(category_id)
    title = I18n.t('election.title', position: position)

    topic = Topic.new(title: title, user: Discourse.system_user, category_id: category.id)
    topic.skip_callbacks = true
    topic.ignore_category_auto_close = true
    topic.set_or_create_timer(TopicTimer.types[:close], nil)

    topic.subtype = 'election'
    topic.custom_fields['election_status'] = 'nominate'
    topic.custom_fields['election_position'] = position
    topic.custom_fields['election_nominations'] = []
    topic.custom_fields['election_self_nomination_allowed'] = self_nomination_allowed || false

    if details_url
      topic.custom_fields['election_details_url'] = details_url
    end

    if message
      topic.custom_fields['election_nomination_message'] = message
    end

    topic.save!(validate: false)

    raw = "#{I18n.t('election.nominate.desc')}\n\n"

    if message
      raw << message
    end

    manager = NewPostManager.new(Discourse.system_user, {
      raw: raw,
      topic_id: topic.id,
      cook_method: Post.cook_methods[:raw_html]
    })
    result = manager.perform

    if result.success?
      {topic_url: topic.url}
    else
      {error_message: "Election creation failed"}
    end
  end

  def self.start_election(topic_id)
    topic = Topic.find(topic_id)
    nominations = topic.election_nominations

    if nominations.length < 2
      return { error_message: I18n.t('election.errors.more_nominations') }
    end

    poll_options = ''

    nominations.each do |n|
      poll_options << "\n- [#{n}](#{Discourse.base_url}/users/#{n})"
    end

    content = "[poll type=regular]#{poll_options}\n[/poll]"

    update_election_post(topic_id, content)

    topic.custom_fields['election_status'] = 'electing'
    topic.election_status_changed = true
    topic.save!

    { success: true }
  end

  def self.category_elections(category_id, opts = {})
    query = "INNER JOIN topic_custom_fields
             ON topic_custom_fields.topic_id = topics.id
             AND topic_custom_fields.name = 'election_status'"

    if opts.try(:status)
      query << "AND topic_custom_fields.value = #{opts[:status]}"
    else
      query << "AND (topic_custom_fields.value = 'nominate' OR
                     topic_custom_fields.value = 'electing')"
    end

    if opts.try(:role)
      query << "AND topic_custom_fields.name = 'election_role'
                AND topic_custom_fields.value = #{opts[:role]}"
    end

    Topic.joins(query).where(category_id: category_id)
  end

  ### Nomination CRUD

  def self.set_nominations(topic_id, usernames)
    topic = Topic.find(topic_id)
    nominations = usernames
    existing_nominations = topic.election_nominations

    if Set.new(existing_nominations) == Set.new(usernames)
      return { success: true }
    end

    save_nominations(topic, nominations)

    removed_nominations = existing_nominations.reject{ |n| n.empty? || nominations.include?(n) }

    if removed_nominations.any?
      remove_nomination_statements(topic, removed_nominations)
    end

    added_nominations = usernames.reject{ |u| u.empty? || existing_nominations.include?(u) }

    if added_nominations.any?
      handle_new_nominations(topic, added_nominations)
    end

    { success: true }
  end

  def self.add_nomination(topic_id, username)
    topic = Topic.find(topic_id)
    nominations = topic.election_nominations
    nominations.push(username) unless nominations.include?(username)

    save_nominations(topic, nominations)

    handle_new_nominations(topic, [username])

    { success: true }
  end

  def self.remove_nomination(topic_id, username)
    topic = Topic.find(topic_id)

    save_nominations(topic, topic.election_nominations - [username])

    remove_nomination_statements(topic, [username])

    build_election_post(topic)

    { success: true }
  end

  def self.save_nominations(topic, nominations)
    topic.custom_fields['election_nominations'] = nominations.join('|')
    topic.save!
  end

  def self.handle_new_nominations(topic, new_nominations)
    existing_statements = retrieve_nomination_statements(topic.id, new_nominations)

    if existing_statements.any?
      existing_statements.each do |statement|
        update_nomination_statement(statement)
      end
    else
      build_election_post(topic)
    end
  end

  ## handle nomination statements

  def self.update_nomination_statement(post)
    statements = post.topic.election_nomination_statements
    existing = false
    excerpt = PrettyText.excerpt(post.cooked, 100, keep_emoji_images: true)

    statements.each do |s|
      if s['post_id'] == post.id
        existing = true
        s['excerpt'] = excerpt
      end
    end

    unless existing
      statements.push({
        post_id: post.id,
        username: post.user.username,
        excerpt: excerpt
      })
    end

    save_nomination_statements(post.topic, statements)
  end

  def self.remove_nomination_statements(topic, removed_nominations)
    statements = topic.election_nomination_statements
    removed_statements = []

    removed_nominations.each do |rn|
      statements = statements.reject do |s|
        if s['username'] == rn
          removed_statements.push(s)
          true
        end
      end
    end

    save_nomination_statements(topic, statements)
    update_statement_posts(removed_statements)
  end

  def self.save_nomination_statements(topic, statements)
    topic.custom_fields['election_nomination_statements'] = JSON.generate(statements)
    topic.save!

    build_election_post(topic)
    update_statement_posts(statements)
  end

  def self.retrieve_nomination_statements(topic_id, usernames)
    existing_statements = []

    usernames.each do |u|
      user = User.find_by(username: u)
      user_posts = Post.where(user_id: user.id, topic_id: topic_id)

      if user_posts.any?
        user_statement = user_posts.joins("INNER JOIN post_custom_fields
                                           ON post_custom_fields.post_id = posts.id
                                           AND post_custom_fields.name = 'election_nomination_statement'
                                           AND post_custom_fields.value = 'true'").first
        if user_statement
          existing_statements.push(user_statement)
        end
      end
    end

    existing_statements
  end

  def self.update_statement_posts(statements)
    statements.each do |s|
      s = s.with_indifferent_access
      if s[:post_id]
        post = Post.find(s['post_id'])
        post.publish_change_to_clients!(:revised)
      end
    end
  end

  ### Build and save election post

  def self.build_election_post(topic)
    content = ""
    nominations = topic.election_nominations
    nomination_statements = topic.election_nomination_statements

    if nominations.any?
      content << "<div class='title'>#{I18n.t('election.post.nominated')}</div>"

      content << "<table class='nomination-list'>"

      nominations.each do |n|
        user = User.find_by(username: n)
        avatar_url = user.avatar_template_url.gsub("{size}", "50")

        content << "<tr class='nomination'>"

        content << "<td class='nomination-user'>"
        content << "<div class='trigger-user-card' href='/u/#{n}' data-user-card='#{n}'>"
        content << "<img alt='' width='25' height='25' src='#{avatar_url}' class='avatar'>"
        content << "<a class='mention'>@#{n}</a>"
        content << "</div>"
        content << "</td>"

        content << "<td class='nomination-statement'>"

        statement = nomination_statements.find{ |s| s['username'] == n }
        if statement
          post = Post.find(statement['post_id'])
          content << "<a href='#{post.url}'>#{statement['excerpt']}</a>"
        end

        content << "</td>"

        content << "</tr>"
      end

      content << "</table>"
    end

    message = topic.custom_fields['election_message']

    if message
      content << "\n\n #{message}"
    end

    update_election_post(topic.id, content)
  end

  def self.update_election_post(topic_id, content)
    election_post = Post.find_by(topic_id: topic_id, post_number: 1)

    revisor = PostRevisor.new(election_post, election_post.topic)
    revisor.revise!(election_post.user, { raw: content }, { skip_revision: true })

    election_post.publish_change_to_clients!(:revised, { reload_topic: true })
  end
end
