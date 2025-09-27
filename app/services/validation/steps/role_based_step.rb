module Validation
  module Steps
    class RoleBasedStep
      # Повертає [out_kept_tempfile, removed_count, out_rejected_tempfile]
      def call(in_path:)
        cfg = Validation::RoleConfig.new

        out_kept = Tempfile.new(['emails_role_kept', '.txt'], binmode: true)
        out_rej  = Tempfile.new(['emails_role_rej',  '.txt'], binmode: true)
        removed = 0

        File.foreach(in_path, chomp: true) do |line|
          email = line.to_s.strip
          next if email.empty?

          local, domain = email.downcase.split('@', 2)
          unless local && domain
            out_rej.write(email << "\n")
            removed += 1
            next
          end

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

      # Порядок перевірок підібрано від "вузької" до "ширшої" відповідності:
      #  1) токени (чіткі збіги)
      #  2) спеціальні фрази (service-desk, customer-support)
      #  3) префікс/суфікс службових токенів
      #  4) exact-match після dot-insensitive нормалізації (gmail*)
      def role_like?(local, domain, cfg)
        raw = local.split('+', 2).first.to_s # зберігаємо роздільники
        return false if raw.empty?

        # --- 1) Токени за роздільниками (крапка/нижнє підкреслення/дефіс/інше) ---
        tokens = raw.split(/[^[:alnum:]]+/).reject(&:empty?)
        return true if tokens.any? { |t| cfg.local_parts_set.include?(t) }

        # --- 2) Фрази (об'єднані словосполучення) ---
        if cfg.phrases_regex && cfg.phrases_regex.match?(raw)
          return true
        end

        # --- 3) Префікс/Суфікс — працює краще для коротких токенів (it, hr, pr, qa) ---
        if cfg.prefix_regex && cfg.prefix_regex.match?(raw)
          # для коротких токенів дозволяємо тільки prefix/suffix або коли токен — самостійний елемент
          return true
        end
        if cfg.suffix_regex && cfg.suffix_regex.match?(raw)
          return true
        end

        # --- 4) exact-match після dot-insensitive нормалізації (gmail-подібні домени) ---
        if cfg.dot_insensitive_domains_set.include?(domain)
          exact = raw.delete('.')
          return true if cfg.local_parts_set.include?(exact)
        end

        false
      end
    end
  end
end
