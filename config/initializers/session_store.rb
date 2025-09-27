# config/initializers/session_store.rb
REDIS_URL = ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')

Rails.application.config.session_store :redis_session_store,
  key: '_new_email_validator_session',
  redis: {
    url: REDIS_URL
    # ВАЖЛИВО: БЕЗ :namespace тут! Redis.new не приймає цей ключ.
  },
  key_prefix: 'session:',     # це і є "неймспейс" для ключів сесій
  expire_after: 1.day,
  same_site: :lax,
  secure: Rails.env.production?
