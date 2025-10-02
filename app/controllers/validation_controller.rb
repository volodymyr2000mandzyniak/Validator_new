class ValidationController < ApplicationController
  before_action :set_uploaded_file

  def show
    scope = params[:scope].presence || 'valid'

    # Вхідні рядки (до будь-яких фільтрів)
    @total_in = line_count_blob(@uploaded_file.original_file&.blob)

    # Валідні (після всіх обраних фільтрів)
    if @uploaded_file.processed_file.attached?
      @processed   = true
      @valid_count = line_count_blob(@uploaded_file.processed_file.blob)
    else
      @processed   = false
      @valid_count = 0
    end

    # Звіти по категоріях (рахуємо рядки у кожному артефакті)
    @dup_count        = attached_count(@uploaded_file.report_duplicates)
    @dns_local_count  = attached_count(@uploaded_file.report_dns_local)
    @dns_online_count = attached_count(@uploaded_file.report_dns_online)
    @role_count       = attached_count(@uploaded_file.report_role_based)
    @syntax_count     = attached_count(@uploaded_file.report_syntax)

    @dns_count        = @dns_local_count + @dns_online_count
    @invalid_count    = @dup_count + @dns_count + @role_count + @syntax_count

    # Дані прев’ю відповідно до обраного scope
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
      @preview_total = distinct_total

    when 'syntax'
      if @uploaded_file.report_syntax.attached?
        @preview_lines, @preview_total = read_blob_lines(@uploaded_file.report_syntax.blob, limit: 100)
      else
        @preview_lines, @preview_total = [], 0
      end

    when 'role'
      if @uploaded_file.report_role_based.attached?
        @preview_lines, @preview_total = read_blob_lines(@uploaded_file.report_role_based.blob, limit: 100)
      else
        @preview_lines, @preview_total = [], 0
      end

    when 'invalid'
      blobs = []
      blobs << @uploaded_file.report_duplicates.blob    if @uploaded_file.report_duplicates.attached?
      blobs << @uploaded_file.report_dns_local.blob     if @uploaded_file.report_dns_local.attached?
      blobs << @uploaded_file.report_dns_online.blob    if @uploaded_file.report_dns_online.attached?
      blobs << @uploaded_file.report_role_based.blob    if @uploaded_file.report_role_based.attached?
      blobs << @uploaded_file.report_syntax.blob        if @uploaded_file.report_syntax.attached?
      @preview_lines, distinct_total = union_preview(blobs, limit: 100)
      @preview_total = distinct_total

    else
      # дефолт — valid
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
      syntax:            ActiveModel::Type::Boolean.new.cast(params[:syntax]),
      dns_local:         ActiveModel::Type::Boolean.new.cast(params[:dns_local]),
      dns_online:        ActiveModel::Type::Boolean.new.cast(params[:dns_online]),
      role_based:        ActiveModel::Type::Boolean.new.cast(params[:role_based])
    }

    if opts.values.none?
      redirect_to validation_path(file_id: @uploaded_file.id),
                  alert: "Оберіть хоча б один фільтр (Синтаксис / Дедуплікація / DNS / DNS online / Службові)"
      return
    end

    result = Validation::Pipeline.new(@uploaded_file, opts).call

    flash[:removed_duplicates] = result[:removed_duplicates] if result.key?(:removed_duplicates)
    flash[:removed_dns_local]  = result[:removed_dns_local]  if result.key?(:removed_dns_local)
    flash[:removed_dns_online] = result[:removed_dns_online] if result.key?(:removed_dns_online)
    flash[:removed_role]       = result[:removed_role]       if result.key?(:removed_role)
    flash[:removed_syntax]     = result[:removed_syntax]     if result.key?(:removed_syntax)

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

  def attached_count(attachment)
    attachment&.attached? ? line_count_blob(attachment.blob) : 0
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
