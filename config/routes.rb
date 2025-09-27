Rails.application.routes.draw do
  # Головна сторінка (не чіпаємо назву/місце)
  root 'home#index'

  # Завантаження файлів
  resources :file_uploads, only: %i[new create]

  # Валідація
  get  '/validation',          to: 'validation#show',         as: :validation
  post '/validation/process',  to: 'validation#process_file', as: :process_validation
  get  '/validation/download', to: 'validation#download_file',as: :download_validation
end
