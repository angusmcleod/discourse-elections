module DiscourseElections
  class BaseController < ::ApplicationController
    def ensure_is_elections_admin
      raise Discourse::InvalidAccess.new unless current_user && current_user.is_elections_admin?
    end

    def ensure_is_elections_category
      return false unless params.include?(:category_id)

      category = Category.find(params[:category_id])
      unless category.custom_fields["for_elections"]
        raise StandardError.new I18n.t("election.errors.category_not_enabled")
      end
    end

    def render_result(result = {})
      if result[:error_message]
        render json: failed_json.merge(message: result[:error_message])
      else
        render json: success_json.merge(result)
      end
    end
  end
end
