require 'resolv'

module Validation
  module Steps
    class DnsOnlineStep
      DNS_TIMEOUT = 2.0

      def initialize
        @mx_cache = {}
      end

      # Повертає [out_kept_tempfile, removed_count, out_rejected_tempfile]
      def call(in_path:)
        out_kept = Tempfile.new(['emails_dns_live_kept', '.txt'], binmode: true)
        out_rej  = Tempfile.new(['emails_dns_live_rej',  '.txt'], binmode: true)
        removed = 0

        File.foreach(in_path, chomp: true) do |email|
          domain = email.split('@', 2)[1].to_s.downcase
          if mx_exists?(domain)
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
      def mx_exists?(domain)
        return false if domain.empty?
        return @mx_cache[domain] if @mx_cache.key?(domain)

        result = false
        Resolv::DNS.open do |dns|
          dns.timeouts = DNS_TIMEOUT
          mx = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
          result = mx && !mx.empty?
        end
        @mx_cache[domain] = result
      rescue
        @mx_cache[domain] = false
      end
    end
  end
end
