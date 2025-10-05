# app/services/validation/steps/role_based_step.rb
module Validation
  module Steps
    class RoleBasedStep
      # Роздільники для токенів локальної частини
      SEP = /[._+\-]+/

      # Повертає [out_kept_tempfile, removed_count, out_rejected_tempfile]
      def call(in_path:)
        cfg = Validation::RoleConfig.new

        out_kept = Tempfile.new(['emails_role_kept', '.txt'], binmode: true)
        out_rej  = Tempfile.new(['emails_role_rej',  '.txt'], binmode: true)
        removed = 0

        File.foreach(in_path, chomp: true) do |line|
          email = line.to_s.strip
          next if email.empty?

          local, domain = email.split('@', 2)
          unless local && domain
            out_rej.write(email << "\n")
            removed += 1
            next
          end

          local  = local.downcase
          domain = domain.downcase

          if role_like?(local, domain, cfg)
            out_rej.write(email << "\n")
            removed += 1
          else
            out_kept.write(email << "\n")
          end
        end

        out_kept.flush
        out_rej.flush
        [out_kept, removed, out_rej]
      end

      private

      # Порядок перевірок: від вузьких до ширших:
      #  1) токени та їх "безцифрові" варіанти (4004shop -> shop)
      #  2) patterns з YAML (у т.ч. "числа + службове слово")
      #  3) фрази (service-desk / customer-support тощо)
      #  4) префікс/суфікс для коротких токенів (it-, -hr, pr-, qa-)
      #  5) exact-match після dot-insensitive нормалізації (gmail*)
      def role_like?(local, domain, cfg)
        l = normalize_local(local, domain, cfg)
        return false if l.empty?

        candidates = token_candidates(l)

        # 1) Точні збіги токенів проти словника службових локалей
        return true if candidates.any? { |t| cfg.local_parts_set.include?(t) }

        # 2) Регулярні вирази з YAML (patterns_any? або patterns_regex)
        if cfg.respond_to?(:patterns_any?)
          return true if cfg.patterns_any?([l] + candidates)
        elsif cfg.respond_to?(:patterns_regex) && cfg.patterns_regex
          return true if ([l] + candidates).any? { |s| cfg.patterns_regex.match?(s) }
        end

        # 3) Склеєні фрази (service-desk / customer-support)
        if cfg.respond_to?(:phrases_regex) && cfg.phrases_regex
          return true if cfg.phrases_regex.match?(l)
        end

        # 4) Короткі службові як префікс/суфікс (it-, -hr, pr-, qa-)
        if cfg.respond_to?(:prefix_regex) && cfg.prefix_regex
          return true if cfg.prefix_regex.match?(l)
        end
        if cfg.respond_to?(:suffix_regex) && cfg.suffix_regex
          return true if cfg.suffix_regex.match?(l)
        end

        # 5) exact-match після dot-insensitive нормалізації для gmail-подібних доменів
        if dot_insensitive_domain?(cfg, domain)
          exact = l.delete('.')
          return true if cfg.local_parts_set.include?(exact)
        end

        false
      end

      # Нормалізація локалі: зрізати +tag; для gmail-подібних доменів ігнорувати крапки
      def normalize_local(local, domain, cfg)
        s = local.split('+', 2).first.to_s.downcase
        s = s.delete('.') if dot_insensitive_domain?(cfg, domain)
        s
      end

      # Токени + варіанти без цифр: "4004shop.rom" -> ["4004shop","rom","shop"]
      def token_candidates(local)
        base      = local.split(SEP).reject(&:empty?)
        no_digits = base.map { |t| t.gsub(/\d+/, '') }.reject(&:empty?)
        (base + no_digits + [local]).uniq
      end

      # Узгоджена перевірка на "крапка-неважлива" для домену (gmail / googlemail)
      def dot_insensitive_domain?(cfg, domain)
        if cfg.respond_to?(:dot_insensitive_domain?)
          cfg.dot_insensitive_domain?(domain)
        elsif cfg.respond_to?(:dot_insensitive_domains_set)
          cfg.dot_insensitive_domains_set.include?(domain)
        else
          false
        end
      end
    end
  end
end
