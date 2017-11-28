class DiscourseElections::ListController < ::ApplicationController
  def category_list
    params.require(:category_id)

    topics = DiscourseElections::ElectionCategory.topics(params[:category_id],
      statuses: [Topic.election_statuses[:nomination], Topic.election_statuses[:poll]]
    )

    render_serialized(topics, DiscourseElections::ElectionSerializer)
  end
end
