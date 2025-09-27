require 'yaml'
require 'set'

module Validation
  class RoleConfig
    FALLBACK = {
      "local_parts" => %w[admin info support sales help postmaster webmaster abuse security],
      "patterns"    => [ '\bnore?ply\b' ],
      "phrase_patterns" => [],
      "short_tokens" => %w[it hr pr qa],
      "dot_insensitive_domains" => %w[gmail.com googlemail.com]
    }.freeze

    attr_reader :local_parts_set, :patterns_regex, :phrases_regex,
                :dot_insensitive_domains_set, :short_tokens_set,
                :prefix_regex, :suffix_regex

    def initialize
      cfg = load_config # ← головне

      tokens = Array(cfg["local_parts"]).map { |s| s.to_s.strip.downcase }.reject(&:empty?)
      @local_parts_set = tokens.to_set

      @patterns_regex = build_union_regex(Array(cfg["patterns"]))
      @phrases_regex  = build_union_regex(Array(cfg["phrase_patterns"]))

      @short_tokens_set = Array(cfg["short_tokens"]).map(&:downcase).to_set

      @dot_insensitive_domains_set =
        Array(cfg["dot_insensitive_domains"]).map(&:downcase).to_set

      # regex для префікса/суфікса службових токенів
      alts = tokens.grep(/\A[a-z0-9]+\z/).uniq.join('|')
      if alts.empty?
        @prefix_regex = @suffix_regex = nil
      else
        @prefix_regex = Regexp.new("\\A(?:#{alts})(?:[^[:alnum:]]|\\z)", Regexp::IGNORECASE)
        @suffix_regex = Regexp.new("(?:\\A|[^[:alnum:]])(?:#{alts})\\z", Regexp::IGNORECASE)
      end
    end

    private

    # ✅ Використовуємо Rails.config_for — він:
    #  - читає секцію поточного середовища
    #  - коректно застосовує <<: *default (anchors/aliases)
    def load_config
      cfg = Rails.application.config_for(:role_addresses)
      cfg.is_a?(Hash) ? cfg.deep_stringify_keys : FALLBACK
    rescue => _
      FALLBACK
    end

    def build_union_regex(list)
      arr = list.map { |s| s.to_s.strip }.reject(&:empty?)
      return nil if arr.empty?
      Regexp.new(arr.join("|"), Regexp::IGNORECASE)
    end
  end
end
