module Validation
  class Pipeline
    def initialize(uploaded_file, opts = {})
      @uploaded_file = uploaded_file
      @opts = {
        remove_duplicates: false,
        dns_local:         false,
        dns_online:        false,
        role_based:        false 
      }.merge(opts.symbolize_keys)
      @to_cleanup = []
      @metrics = {}
    end

    def call
      io = @uploaded_file.original_file
      raise "No original file" unless io&.attached?

      # STAGE 0: src
      src = tempfile('emails_src')
      src.write(io.download)
      src.flush

      # STAGE 1: normalize
      stage1 = tempfile('emails_norm')
      total_in = 0
      after_norm = 0
      File.foreach(src.path, chomp: true) do |line|
        total_in += 1
        s = line.strip
        next if s.empty?
        stage1.write(s << "\n")
        after_norm += 1
      end
      stage1.flush
      @metrics[:total_in] = total_in
      @metrics[:after_normalize] = after_norm

      current_path = stage1.path

      # STAGE 2: DNS local
      if @opts[:dns_local]
        out_kept, removed, out_rej = Steps::DnsLocalStep.new.call(in_path: current_path)
        @metrics[:removed_dns_local] = removed
        attach_blob(@uploaded_file, :report_dns_local, out_rej, "dns_local_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # STAGE 3: Role-based (службові)
      if @opts[:role_based]
        out_kept, removed, out_rej = Steps::RoleBasedStep.new.call(in_path: current_path)
        @metrics[:removed_role] = removed
        attach_blob(@uploaded_file, :report_role_based, out_rej, "role_based_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # STAGE 4: Deduplicate
      if @opts[:remove_duplicates]
        out_kept, removed, out_dups = Steps::DeduplicateStep.new.call(in_path: current_path)
        @metrics[:removed_duplicates] = removed
        attach_blob(@uploaded_file, :report_duplicates, out_dups, "duplicates_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_dups]
      end

      # STAGE 5: DNS online
      if @opts[:dns_online]
        out_kept, removed, out_rej = Steps::DnsOnlineStep.new.call(in_path: current_path)
        @metrics[:removed_dns_online] = removed
        attach_blob(@uploaded_file, :report_dns_online, out_rej, "dns_online_rejected_#{io.filename}")
        current_path = out_kept.path
        @to_cleanup += [out_kept, out_rej]
      end

      # STAGE 6: final
      total_out = line_count(current_path)
      @metrics[:total_out] = total_out

      # processed_file — фінал
      @uploaded_file.processed_file.attach(
        io: File.open(current_path, 'rb'),
        filename: "processed_#{io.filename}",
        content_type: 'text/plain'
      )

      @metrics
    ensure
      ([src, stage1] + @to_cleanup).compact.each { |f| begin f.close! rescue nil end }
    end

    private

    def tempfile(prefix)
      f = Tempfile.new([prefix, '.txt'], binmode: true)
      @to_cleanup << f
      f
    end

    def line_count(path)
      c = 0
      File.foreach(path) { c += 1 }
      c
    end

    def attach_blob(record, name, tempfile, filename)
      record.public_send(name).attach(
        io: File.open(tempfile.path, 'rb'),
        filename: filename.to_s,
        content_type: 'text/plain'
      )
    end
  end
end
