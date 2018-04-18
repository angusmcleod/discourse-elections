require_dependency 'application_controller'
module ::DiscourseElections
  class Engine < ::Rails::Engine
    engine_name 'discourse_elections'
    isolate_namespace DiscourseElections
  end
end

DiscourseElections::Engine.routes.draw do
  post 'nomination/set-by-username' => 'nomination#set_by_username'
  post 'nomination' => 'nomination#add'
  delete 'nomination' => 'nomination#remove'

  post 'create' => 'election#create'
  put 'set-self-nomination-allowed' => 'election#set_self_nomination_allowed'
  put 'set-status-banner' => 'election#set_status_banner'
  put 'set-status-banner-result-hours' => 'election#set_status_banner_result_hours'
  put 'set-nomination-message' => 'election#set_message'
  put 'set-poll-message' => 'election#set_message'
  put 'set-closed-poll-message' => 'election#set_message'
  put 'set-status' => 'election#set_status'
  put 'set-position' => 'election#set_position'
  put 'set-poll-time' => 'election#set_poll_time'
  put 'start-poll' => 'election#start_poll'
  get 'category-list' => 'list#category_list'
end

Discourse::Application.routes.append do
  mount ::DiscourseElections::Engine, at: 'election'
end
