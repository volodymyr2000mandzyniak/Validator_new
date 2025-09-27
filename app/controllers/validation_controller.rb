# app/controllers/validation_controller.rb
class ValidationController < ApplicationController
  before_action :set_uploaded_file

    def show
    scope       = params[:scope].presence || 'valid'
    @total_in   = line_count_blob(@uploaded_file.original_file&.blob)

    # якщо є фінальний файл — він і є "валідні"
    if @uploaded_file.processed_file.attached?
      @processed    = true
      @valid_count  = line_count_blob(@uploaded_file.processed_file.blob)
    else
      @processed    = false
      @valid_count  = 0
    end

    @dup_count        = @uploaded_file.report_duplicates.attached?   ? line_count_blob(@uploaded_file.report_duplicates.blob)   : 0
    @dns_local_count  = @uploaded_file.report_dns_local.attached?    ? line_count_blob(@uploaded_file.report_dns_local.blob)    : 0
    @dns_online_count = @uploaded_file.report_dns_online.attached?   ? line_count_blob(@uploaded_file.report_dns_online.blob)   : 0
    @role_count       = @uploaded_file.report_role_based.attached?   ? line_count_blob(@uploaded_file.report_role_based.blob)   : 0

    @dns_count     = @dns_local_count + @dns_online_count

    # Найнадійніший спосіб невалідних — як різниця (уникає дублювання між звітами)
    @invalid_count = [@total_in - @valid_count, 0].max

    case scope
    when 'valid'
      blob = (@uploaded_file.processed_file.attached? ? @uploaded_file.processed_file.blob : @uploaded_file.original_file.blob)
      @preview_lines, @preview_total = read_blob_lines(blob, limit: 100)

    when 'duplicates'
      if @uploaded_file.report_duplicates.attached?
        @preview_lines, @preview_total = read_blob_lines(@uploaded_file.report_duplicates.blob, limit: 100)
      else
        @preview_lines, @preview_total = [], 0
      end

    when 'dns'
      blobs = []
      blobs << @uploaded_file.report_dns_local.blob  if @uploaded_file.report_dns_local.attached?
      blobs << @uploaded_file.report_dns_online.blob if @uploaded_file.report_dns_online.attached?
      @preview_lines, distinct_total = union_preview(blobs, limit: 100)
      # для відображення лічильника в лівій панелі залишаємо суму лок+онлайн
      @preview_total = @dns_count

    when 'role'
      if @uploaded_file.report_role_based.attached?
        @preview_lines, @preview_total = read_blob_lines(@uploaded_file.report_role_based.blob, limit: 100)
      else
        @preview_lines, @preview_total = [], 0
      end

    when 'invalid'
      # Усі невалідні: об’єднуємо звіти (distinct), щоб не дублювати однакові адреси
      blobs = []
      blobs << @uploaded_file.report_duplicates.blob  if @uploaded_file.report_duplicates.attached?
      blobs << @uploaded_file.report_dns_local.blob   if @uploaded_file.report_dns_local.attached?
      blobs << @uploaded_file.report_dns_online.blob  if @uploaded_file.report_dns_online.attached?
      blobs << @uploaded_file.report_role_based.blob  if @uploaded_file.report_role_based.attached?
      @preview_lines, distinct_total = union_preview(blobs, limit: 100)
      # лівий лічильник уже показує @invalid_count як total - valid; лишаємо його для консистентності
      @preview_total = @invalid_count

    else
      blob = (@uploaded_file.processed_file.attached? ? @uploaded_file.processed_file.blob : @uploaded_file.original_file.blob)
      @preview_lines, @preview_total = read_blob_lines(blob, limit: 100)
    end

    @current_scope = scope
  rescue => e
    redirect_to new_file_upload_path, alert: "Файл не знайдено або пошкоджений: #{e.message}"
  end

  def process_file
    opts = {
      remove_duplicates: ActiveModel::Type::Boolean.new.cast(params[:remove_duplicates]),
      dns_local:         ActiveModel::Type::Boolean.new.cast(params[:dns_local]),
      dns_online:        ActiveModel::Type::Boolean.new.cast(params[:dns_online]),
      role_based:        ActiveModel::Type::Boolean.new.cast(params[:role_based])
    }

    if opts.values.none?
      redirect_to validation_path(file_id: @uploaded_file.id),
                  alert: "Оберіть хоча б один фільтр (Дедуплікація / DNS / DNS online / Службові адреси)"
      return
    end

    result = Validation::Pipeline.new(@uploaded_file, opts).call

    # необов’язково, але хай залишиться для підказок
    flash[:duplicates_removed] = result[:removed_duplicates] if result.key?(:removed_duplicates)
    flash[:dns_local_removed]  = result[:removed_dns_local]  if result.key?(:removed_dns_local)
    flash[:dns_online_removed] = result[:removed_dns_online] if result.key?(:removed_dns_online)
    flash[:role_removed]       = result[:removed_role]       if result.key?(:removed_role)

    redirect_to validation_path(file_id: @uploaded_file.id)
  end

  def download_file
    unless @uploaded_file.processed_file.attached?
      return redirect_to validation_path(@uploaded_file), alert: "Спочатку виконайте обробку файлу"
    end

    blob = @uploaded_file.processed_file.blob
    send_data blob.download, filename: blob.filename.to_s, type: blob.content_type
  end

  private

  def set_uploaded_file
    @uploaded_file = UploadedFile.find(params[:file_id])
  end

  # Рахує кількість рядків у blob (стрімінг)
  def line_count_blob(blob)
    return 0 unless blob
    c = 0
    blob.open(tmpdir: Dir.tmpdir) { |f| File.foreach(f.path) { c += 1 } }
    c
  end

  # Повертає [масив_рядків_без_переносу, загальна_кількість]
  def read_blob_lines(blob, limit:)
    return [[], 0] unless blob
    preview = []
    total = 0
    blob.open(tmpdir: Dir.tmpdir) do |file|
      File.foreach(file.path, chomp: true) do |line|
        total += 1
        preview << line
        break if preview.size >= limit
      end
    end
    [preview, total]
  end

  # Об’єднання кількох blob’ів у distinct-перелік (для invalid/dns)
  # Повертає [preview_lines, distinct_total]
  def union_preview(blobs, limit:)
    require 'set'
    set = Set.new
    preview = []
    blobs.each do |blob|
      blob.open(tmpdir: Dir.tmpdir) do |file|
        File.foreach(file.path, chomp: true) do |line|
          next if line.strip.empty?
          unless set.include?(line)
            set.add(line)
            preview << line if preview.size < limit
          end
        end
      end
    end
    [preview, set.size]
  end
end
