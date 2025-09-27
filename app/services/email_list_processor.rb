class EmailListProcessor
  def initialize(uploaded_file)
    @uploaded_file = uploaded_file
  end

  # Повертає:
  # {
  #   total_in:          <рядків на вході>,
  #   unique_out:        <рядків після дедупу>,
  #   removed_duplicates:<скільки дублікатів прибрано>
  # }
  def call
    io = @uploaded_file.original_file
    raise 'No original file' unless io&.attached?

    src = Tempfile.new(['emails_src', '.txt'], binmode: true)
    src.write(io.download)
    src.flush

    # Нормалізація: trim + пропуск порожніх (щоб дубль "a@b.com " = "a@b.com")
    normalized = Tempfile.new(['emails_norm', '.txt'], binmode: true)
    total_in = 0
    File.foreach(src.path, chomp: true) do |line|
      total_in += 1
      email = line.strip
      next if email.empty?
      normalized.write(email << "\n")
    end
    normalized.flush

    # Дедуп: sort -u — RAM-safe
    processed = Tempfile.new(['emails_processed', '.txt'], binmode: true)
    system(%(sort -u "#{normalized.path}" -o "#{processed.path}"))
    raise "Failed to run `sort -u`" unless $?.success?

    unique_out = line_count(processed.path)
    removed_duplicates = line_count(normalized.path) - unique_out

    # Зберігаємо результат
    @uploaded_file.processed_file.attach(
      io: File.open(processed.path, 'rb'),
      filename: "processed_#{io.filename}",
      content_type: 'text/plain'
    )

    {
      total_in: total_in,
      unique_out: unique_out,
      removed_duplicates: removed_duplicates
    }
  ensure
    [src, normalized, processed].compact.each { |f| begin f.close! rescue nil end }
  end

  private

  def line_count(path)
    c = 0
    File.foreach(path) { c += 1 }
    c
  end
end
