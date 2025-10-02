# app/services/validation/pipeline.rb
module Validation
  class Pipeline
    # opts — прапорці, які кроки вмикати
    #   remove_duplicates: true/false  — видалення дублікатів (і звіт з дублікатами)
    #   syntax:            true/false  — НОВЕ: базова валідність/якість email (формат, послідовності, повтоpи, довжини…)
    #   dns_local:         true/false  — локальна DNS-перевірка (білий список доменів)
    #   dns_online:        true/false  — онлайн MX-перевірка
    #   role_based:        true/false  — службові адреси (role/catch-all)
    def initialize(uploaded_file, opts = {})
      @uploaded_file = uploaded_file
      @opts = {
        remove_duplicates: false,
        syntax:            false,  # ← додано
        dns_local:         false,
        dns_online:        false,
        role_based:        false
      }.merge(opts.symbolize_keys)

      @to_cleanup = []  # усі тимчасові файли для гарантованого прибирання
      @metrics    = {}  # метрики знятих адрес по кожному кроку (для діагностики/flash)
    end

    # Головний метод конвеєра. Повертає @metrics (опційно використовуємо у контролері або для логів).
    def call
      io = @uploaded_file.original_file
      raise "No original file" unless io&.attached?

      # =======================
      # STAGE 0: Джерело (src)
      # =======================
      # Копіюємо blob в тимчасовий файл. Працюємо лише зі стрімами/файлами — жодних великих об’ємів у пам’яті.
      src = tempfile('emails_src')
      src.write(io.download)
      src.flush

      # =======================================
      # STAGE 1: Нормалізація (trim/skip blank)
      # =======================================
      # Прибираємо пробіли, пропускаємо порожні рядки. Рахуємо вхідні/після нормалізації.
      stage1      = tempfile('emails_norm')
      total_in    = 0
      after_norm  = 0
      File.foreach(src.path, chomp: true) do |line|
        total_in += 1
        s = line.strip
        next if s.empty?
        stage1.write(s << "\n")
        after_norm += 1
      end
      stage1.flush
      @metrics[:total_in]        = total_in
      @metrics[:after_normalize] = after_norm

      current_path = stage1.path

      # ==========================================
      # STAGE 2: СИНТАКСИС / ЯКІСТЬ (НОВИЙ КРОК)
      # ==========================================
      # Відсікаємо все, що не схоже на адекватний email для розсилок:
      #  - рівно один '@'; локаль/домен без заборонених конструкцій
      #  - локаль не лише з цифр; без ".." та крапок на краях
      #  - довжини: локаль [min..max], email ≤ max
      #  - послідовності (abc, 123, qwerty…), повтор одного символу (aaaa), повторювані підрядки (abcabc)
      if @opts[:syntax]
        out_kept, removed, out_rej = Steps::SyntaxStep.new.call(in_path: current_path)
        @metrics[:removed_syntax] = removed
        attach_blob(@uploaded_file, :report_syntax, out_rej, "syntax_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # =================================
      # STAGE 3: DNS локальна (whitelist)
      # =================================
      # Пропускаємо лише домени з білого списку (gmail.com / yahoo.com / …).
      if @opts[:dns_local]
        out_kept, removed, out_rej = Steps::DnsLocalStep.new.call(in_path: current_path)
        @metrics[:removed_dns_local] = removed
        attach_blob(@uploaded_file, :report_dns_local, out_rej, "dns_local_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # =======================================
      # STAGE 4: Службові / role-based мейли
      # =======================================
      # Відсіюємо info@, support@, admin@, *_shop, *_support і т.д. (за словником + евристики).
      if @opts[:role_based]
        out_kept, removed, out_rej = Steps::RoleBasedStep.new.call(in_path: current_path)
        @metrics[:removed_role] = removed
        attach_blob(@uploaded_file, :report_role_based, out_rej, "role_based_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # ================================
      # STAGE 5: Дедуплікація (duplicates)
      # ================================
      # Видаляємо повтори (звітуємо всі «зайві» входження). Робимо після role/dns/syntax,
      # аби duplicates не «змішувались» із причинами відхилення адрес — але
      # якщо хочеш більше економити MX-запити, можна підняти цей крок вище.
      if @opts[:remove_duplicates]
        out_kept, removed, out_dups = Steps::DeduplicateStep.new.call(in_path: current_path)
        @metrics[:removed_duplicates] = removed
        attach_blob(@uploaded_file, :report_duplicates, out_dups, "duplicates_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_dups]
      end

      # =======================================
      # STAGE 6: DNS online (живі MX-запити)
      # =======================================
      # Повільний, але найточніший етап — робимо тільки за потреби і вже на «очищеному» списку.
      if @opts[:dns_online]
        out_kept, removed, out_rej = Steps::DnsOnlineStep.new.call(in_path: current_path)
        @metrics[:removed_dns_online] = removed
        attach_blob(@uploaded_file, :report_dns_online, out_rej, "dns_online_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # =====================
      # STAGE 7: Фінализація
      # =====================
      total_out = line_count(current_path)
      @metrics[:total_out] = total_out

      # processed_file — головний, фінальний артефакт
      @uploaded_file.processed_file.attach(
        io: File.open(current_path, 'rb'),
        filename: "processed_#{io.filename}",
        content_type: 'text/plain'
      )

      @metrics
    ensure
      # Акуратне прибирання усіх тимчасових файлів
      ([src, stage1] + @to_cleanup).compact.each do |f|
        begin f.close! rescue nil end
      end
    end

    private

    # Створює tempfile і реєструє його для подальшого прибирання.
    def tempfile(prefix)
      f = Tempfile.new([prefix, '.txt'], binmode: true)
      @to_cleanup << f
      f
    end

    # Швидкий підрахунок рядків у файлі (потоково).
    def line_count(path)
      c = 0
      File.foreach(path) { c += 1 }
      c
    end

    # Прикріпити текстовий артефакт до ActiveStorage (звіт або фінал).
    def attach_blob(record, name, tempfile, filename)
      record.public_send(name).attach(
        io: File.open(tempfile.path, 'rb'),
        filename: filename.to_s,
        content_type: 'text/plain'
      )
    end
  end
end
