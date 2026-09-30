Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "opportunities#index"

  get "profile", to: "profile#show", as: :profile
  post "profile/resume", to: "profile#save_resume", as: :save_resume
  post "profile/target_roles", to: "profile#save_target_roles", as: :save_target_roles
  post "profile/preferences", to: "profile#save_preferences", as: :save_preferences

  get "opportunities", to: "opportunities#index", as: :opportunities
  post "opportunities/search", to: "opportunities#search", as: :search_opportunities
  post "opportunities/:id/state", to: "opportunities#update_state", as: :opportunity_state

  get "history", to: "history#index", as: :history
end
