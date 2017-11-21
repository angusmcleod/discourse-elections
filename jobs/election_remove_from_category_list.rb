module Jobs
  class ElectionRemoveFromCategoryList < Jobs::Base
    def execute(args)
      if CategoryCustomField.exists?(category_id: args[:category_id], name: 'election_list')
        category = Category.find(args[:category_id])
        new_list = category.election_list.reject { |e| e['topic_id'].to_i === args[:topic_id].to_i }
        category.custom_fields['election_list'] = JSON.generate(new_list)
        category.save_custom_fields(true)
      end
    end
  end
end
