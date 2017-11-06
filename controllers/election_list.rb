class DiscourseElections::ElectionListController < ::ApplicationController
  def category_list
    params.require(:category_id)

    topics = DiscourseElections::ElectionTopic.list_by_category(params[:category_id],
      statuses: [Topic.election_statuses[:nomination], Topic.election_statuses[:poll]]
    )

    render_serialized(topics, DiscourseElections::ElectionSerializer)
  end
end
