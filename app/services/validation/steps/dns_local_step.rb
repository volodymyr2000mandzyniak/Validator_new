require 'set'

module Validation
  module Steps
    class DnsLocalStep
      # Повертає [out_kept_tempfile, removed_count, out_rejected_tempfile]
      def call(in_path:)
        allowed = Validation::DnsWhitelist.load # -> Set
        out_kept = Tempfile.new(['emails_dns_local_kept', '.txt'], binmode: true)
        out_rej  = Tempfile.new(['emails_dns_local_rej',  '.txt'], binmode: true)
        removed = 0

        File.foreach(in_path, chomp: true) do |email|
          email = email.strip
          next if email.empty?

          domain = domain_of(email)
          if domain && valid_domain_format?(domain) && allowed.include?(domain)
            out_kept.write(email << "\n")
          else
            out_rej.write(email << "\n")
            removed += 1
          end
        end

        out_kept.flush
        out_rej.flush
        [out_kept, removed, out_rej]
      end

      private
      def domain_of(email)
        _, domain = email.downcase.split('@', 2)
        domain&.strip
      end

      def valid_domain_format?(domain)
        /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/.match?(domain)
      end
    end
  end
end
