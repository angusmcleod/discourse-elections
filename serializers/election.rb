class DiscourseElections::ElectionSerializer < ApplicationSerializer
  attributes :position, :relative_url, :status

  def position
    object.custom_fields['election_position']
  end

  def status
    object.election_status
  end
end
