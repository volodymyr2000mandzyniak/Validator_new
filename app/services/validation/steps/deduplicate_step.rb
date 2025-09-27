module Validation
  module Steps
    class DeduplicateStep
      # Повертає [out_kept_tempfile, removed_count, out_duplicates_tempfile]
      def call(in_path:)
        out_kept = Tempfile.new(['emails_dedup', '.txt'], binmode: true)
        ok = system(%(sort -u "#{in_path}" -o "#{out_kept.path}"))
        raise "Failed to run `sort -u`" unless ok && $?.success?

        before = line_count(in_path)
        after  = line_count(out_kept.path)
        removed = before - after

        # Сформуємо список “дублікати (distinct)” RAM-safe:
        #   sort input | uniq -d  -> кожне значення, що зустрічалось >1 раз
        out_dups = Tempfile.new(['emails_duplicates', '.txt'], binmode: true)
        ok2 = system(%(sort "#{in_path}" | uniq -d > "#{out_dups.path}"))
        raise "Failed to produce duplicates list" unless ok2 && $?.success?

        [out_kept, removed, out_dups]
      end

      private
      def line_count(path)
        c = 0
        File.foreach(path) { c += 1 }
        c
      end
    end
  end
end
