require_dependency 'user'
class ::User
  def is_elections_admin?
    if SiteSetting.elections_admin_moderator
      staff?
    else
      admin?
    end
  end

  def election_nominations
    @election_nominations ||= begin
      if TopicCustomField.exists?(name: 'election_nominations', value: id)
        TopicCustomField.where(name: 'election_nominations', value: id).pluck(:topic_id)
      else
        []
      end
    end
  end

  def election_nominee_title
    @election_nominee_title ||= begin
      if election_nominations.any?
        topic_id = election_nominations[0]

        if Topic.exists?(topic_id) && topic = Topic.find(topic_id)
          I18n.t('election.post.nominee_title',
            url: topic.url,
            position: topic.custom_fields['election_position'])
        end
      else
        nil
      end
    end
  end
end
