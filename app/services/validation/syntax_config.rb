module Validation
  class SyntaxConfig
    FALLBACK = {
      "min_local_len" => 5,
      "max_local_len" => 64,
      "max_email_len" => 254,
      "max_consecutive_same" => 4,
      "min_repeat_total_len" => 6,
      "min_repeat_unit_len" => 2,
      "min_seq_len_letters" => 3,
      "min_seq_len_digits" => 3,
      "sequence_words" => %w[qwerty asdf zxc qwertyuiop password admin abc 123 12345]
    }.freeze

    attr_reader :opts

    def initialize
      raw = Rails.application.config_for(:email_syntax)
      @opts = normalize!(raw.is_a?(Hash) ? raw.deep_stringify_keys : FALLBACK.dup)
    rescue
      @opts = normalize!(FALLBACK.dup)
    end

    def [](key) = @opts[key.to_s]

    private

    # Нормалізуємо типи, щоб не падало на Integer/Boolean/Nil і под.
    def normalize!(h)
      h["min_local_len"]        = h["min_local_len"].to_i
      h["max_local_len"]        = h["max_local_len"].to_i
      h["max_email_len"]        = h["max_email_len"].to_i
      h["max_consecutive_same"] = h["max_consecutive_same"].to_i
      h["min_repeat_total_len"] = h["min_repeat_total_len"].to_i
      h["min_repeat_unit_len"]  = h["min_repeat_unit_len"].to_i
      h["min_seq_len_letters"]  = h["min_seq_len_letters"].to_i
      h["min_seq_len_digits"]   = h["min_seq_len_digits"].to_i

      # ГОЛОВНЕ: усі слова — у рядки
      seq = Array(h["sequence_words"])
      h["sequence_words"] = seq.map { |w| w.to_s }.reject(&:empty?)

      h
    end
  end
end
