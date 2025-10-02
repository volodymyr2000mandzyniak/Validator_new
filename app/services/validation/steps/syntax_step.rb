# Перевірка “виглядає як адекватна адреса для розсилок”
# Правила:
#  - рівно один '@'; локальна частина й домен присутні
#  - локаль: [a-z0-9._+-], не починається/закінчується крапкою, без двох крапок підряд
#  - домен: повинен мати крапку, лише [a-z0-9.-], без підряд '..', кожний лейбл не починається/не закінчується '-'
#  - довжини: локаль ∈ [min_local_len..max_local_len], email ≤ max_email_len
#  - локаль не може бути лише цифрами
#  - послідовності: abc, 123, qwerty…; довгі повтори одного символу; повторювані підрядки (abcabc, romromrom)
module Validation
  module Steps
    class SyntaxStep
      def initialize
        @cfg = Validation::SyntaxConfig.new
      end

      # Повертає [kept_tempfile, removed_count, rejected_tempfile]
      def call(in_path:)
        out_kept = Tempfile.new(['emails_syntax_kept', '.txt'], binmode: true)
        out_rej  = Tempfile.new(['emails_syntax_rej',  '.txt'], binmode: true)
        removed = 0

        File.foreach(in_path, chomp: true) do |line|
          email = line.to_s.strip
          next if email.empty?

          if bad_email?(email)
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

      def bad_email?(email)
        s = email.downcase
        return true unless one_at?(s)

        local, domain = s.split('@', 2)
        return true unless local && domain

        return true if s.size > @cfg["max_email_len"].to_i
        return true unless basic_local_ok?(local)
        return true unless basic_domain_ok?(domain)

        return true if local.length < @cfg["min_local_len"].to_i || local.length > @cfg["max_local_len"].to_i
        return true if local_numeric_only?(local)
        return true if long_same_run?(local)
        return true if repeated_substring?(local)
        return true if has_sequences?(local)

        false
      end

      # ==== базові перевірки ====

      def one_at?(s)
        s.count('@') == 1 && !s.include?(' ')
      end

      def basic_local_ok?(local)
        # тільки a-z0-9._+- ; не починається/закінчується крапкою; без '..'
        return false unless /\A[a-z0-9._+\-]+\z/.match?(local)
        return false if local.start_with?('.') || local.end_with?('.')
        return false if local.include?('..')
        true
      end

      def basic_domain_ok?(domain)
        # має крапку; без '..'; тільки a-z0-9.- ; лейбли коректні
        return false if domain.start_with?('.') || domain.end_with?('.')
        return false if domain.include?('..')
        return false unless domain.include?('.')
        return false unless /\A[a-z0-9.\-]+\z/.match?(domain)

        labels = domain.split('.')
        return false if labels.any?(&:empty?)
        labels.each do |lab|
          return false if lab.start_with?('-') || lab.end_with?('-')
          return false unless /\A[a-z0-9\-]+\z/.match?(lab)
          return false if lab.length > 63
        end
        true
      end

      # ==== інформативні/евристичні перевірки ====

      def local_numeric_only?(local)
        /\A\d+\z/.match?(local)
      end

      def long_same_run?(local)
        k = @cfg["max_consecutive_same"].to_i.clamp(2, 10)
        /(.)(\1){#{k-1},}/.match?(local) # k однакових підряд, напр. aaaa
      end

      def repeated_substring?(local)
        min_total = @cfg["min_repeat_total_len"].to_i
        min_unit  = @cfg["min_repeat_unit_len"].to_i
        s = local
        return false if s.length < min_total

        # шукаємо u, що повторюється ≥2 разів
        (min_unit..(s.length / 2)).each do |len|
          next unless (s.length % len).zero?
          u = s[0, len]
          times = s.length / len
          return true if u * times == s
        end
        false
      end

      def has_sequences?(local)
        l = local
      
        # літера/цифра тільки
        alpha = l.gsub(/[^a-z]/, '')
        digit = l.gsub(/[^0-9]/, '')
      
        # послідовності a..z і 0..9 (і у зворотному порядку)
        return true if seq_run?(alpha, @cfg["min_seq_len_letters"].to_i, 'abcdefghijklmnopqrstuvwxyz')
        return true if seq_run?(alpha, @cfg["min_seq_len_letters"].to_i, 'zyxwvutsrqponmlkjihgfedcba')
      
        return true if seq_run?(digit, @cfg["min_seq_len_digits"].to_i, '0123456789')
        return true if seq_run?(digit, @cfg["min_seq_len_digits"].to_i, '9876543210')
      
        # БЕЗПЕЧНА ОБРОБКА: все у строки, потім downcase
        words = Array(@cfg["sequence_words"]).map { |w| w.to_s.downcase }.reject(&:empty?)
        return true if words.any? { |w| w.size >= 3 && l.include?(w) }
      
        false
      end


      def seq_run?(s, min_len, alphabet)
        return false if min_len <= 1
        return false if s.length < min_len
        # знаходимо довгу підпослідовність по "алфавіту"
        longest = 1
        curr = 1
        (1...s.length).each do |i|
          prev = s[i - 1]
          cur  = s[i]
          if alphabet.include?(prev) && alphabet.include?(cur) && alphabet.index(cur) == alphabet.index(prev) + 1
            curr += 1
            longest = [longest, curr].max
          else
            curr = 1
          end
        end
        longest >= min_len
      end
    end
  end
end
