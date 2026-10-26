Rails.application.routes.draw do
  # Autenticação
  post "/signup", to: "users#create"
  post "/login", to: "authentication#login"
  delete "/logout", to: "authentication#logout"
  get "/me", to: "users#me"

  # Cursos e aulas
  resources :courses, only: %i[index show create update destroy] do
    resources :lessons, only: %i[index create]
  end
  resources :lessons, only: %i[show update destroy]

  # Operação (sem autenticação de usuário)
  get "/health", to: "health#ready"
  get "/health/live", to: "health#live"
  get "/health/ready", to: "health#ready"
  get "/metrics", to: "metrics#show"
end
