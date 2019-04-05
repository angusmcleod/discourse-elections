Site.preloaded_category_custom_fields << 'election_list' if Site.respond_to? :preloaded_category_custom_fields

require_dependency 'category'
class Category
  def election_list
    if list = self.custom_fields['election_list']
      list = ::JSON.parse(list) if list.is_a?(String)
      [list].flatten
    else
      []
    end
  end
end

class DiscourseElections::ElectionCategory
  def self.update_election_list(category_id, topic_id, opts = {})
    category = Category.find(category_id)
    topic = Topic.find(topic_id)

    list = category.election_list.reject { |e| e && e['topic_id'].to_i === topic_id.to_i }
    status = opts[:status] || topic.election_status
    banner = opts[:banner] || topic.election_status_banner

    election_params = {
      topic_id: topic_id,
      topic_url: topic.relative_url,
      status: status,
      position: topic.election_position,
      banner: banner.to_s == "true"
    }

    election_params[:time] = opts[:time] if opts[:time]

    category.custom_fields['election_list'] = JSON.generate(list.push(election_params))
    category.save_custom_fields(true)
    category.publish_category

    if topic.election_status == Topic.election_statuses[:closed_poll]
      highlight_hours = topic.election_status_banner_result_hours
      Jobs.enqueue_at(highlight_hours.hours.from_now, :election_remove_from_category_list,
        category_id: category.id,
        topic_id: topic.id
      )
    else
      Jobs.cancel_scheduled_job(:election_remove_from_category_list)
    end
  end

  def self.topics(category_id, opts = {})
    query = "INNER JOIN topic_custom_fields
             ON topic_custom_fields.topic_id = topics.id
             AND topic_custom_fields.name = 'election_status'"

    if opts[:statuses]
      statuses = [*opts[:statuses]]
      status_string = ''
      statuses.each_with_index do |s, i|
        status_string << "\'#{s}\'"
        status_string << "," if i < statuses.length - 1
      end

      query << " AND topic_custom_fields.value IN (#{status_string})"
    end

    topics = Topic.where(category_id: category_id).joins(query)

    if opts[:roles]
      roles = [*opts[:roles]]
      role_string = ''
      roles.each_with_index do |s, i|
        role_string << "\'#{s}\'"
        role_string << "," if i < roles.length - 1
      end

      topics.joins("INNER JOIN topic_custom_fields
                    ON topic_custom_fields.topic_id = topics.id
                    AND topic_custom_fields.name = 'election_position'
                    AND topic_custom_fields.value IN (#{role_string})")
    end

    topics
  end
end
