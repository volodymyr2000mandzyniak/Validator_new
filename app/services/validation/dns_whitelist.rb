# app/services/validation/dns_whitelist.rb
require 'yaml'
require 'set'

module Validation
  class DnsWhitelist
    DEFAULT = %w[
      gmail.com yahoo.com outlook.com hotmail.com live.com icloud.com
      yandex.ru yandex.com ukr.net i.ua meta.ua proton.me protonmail.com zoho.com
    ].to_set

    PATH = Rails.root.join('config', 'validation', 'dns_whitelist.yml')

    # Повертає Set доменів (нижній регістр), або DEFAULT, якщо файл відсутній/порожній/зіпсований
    def self.load
      return DEFAULT unless File.exist?(PATH)

      raw = YAML.safe_load(File.read(PATH))

      list = case raw
              when Array
                raw
              when String
                # Підтримка випадку, коли всі домени записали в один рядок
                raw.split(/\s+/)
              else
                []
              end

      list = list.map { |d| d.to_s.downcase.strip }.reject(&:empty?)
      list.any? ? list.to_set : DEFAULT
    rescue
      DEFAULT
    end
  end
end
