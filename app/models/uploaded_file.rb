class UploadedFile < ApplicationRecord
  has_one_attached :original_file
  has_one_attached :processed_file

  has_one_attached :report_duplicates     # список ДУБЛІКАТНИХ email (distinct)
  has_one_attached :report_dns_local      # рядки, відкинуті локальним DNS
  has_one_attached :report_dns_online     # рядки, відкинуті online DNS
  has_one_attached :report_role_based     #
  has_one_attached :report_role_based_meta
  has_one_attached :report_syntax
end
