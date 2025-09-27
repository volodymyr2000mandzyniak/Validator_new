# app/controllers/file_uploads_controller.rb
class FileUploadsController < ApplicationController
  def new
    @uploaded_file = UploadedFile.new

    if params[:file_id]
      @uploaded_file = UploadedFile.find_by(id: params[:file_id])
      redirect_to new_file_upload_path unless @uploaded_file   # <-- тут
    end
  end

  def create
    @uploaded_file = UploadedFile.new
    @uploaded_file.original_file.attach(params.require(:uploaded_file).fetch(:original_file))

    if @uploaded_file.save
      respond_to do |format|
        format.html { redirect_to new_file_upload_path(file_id: @uploaded_file.id), notice: 'Файл успішно завантажено!' }  # <-- і тут
        format.json { render json: { success: true, file_id: @uploaded_file.id, message: 'Файл успішно завантажено' } }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = 'Не вдалося завантажити файл: ' + @uploaded_file.errors.full_messages.join(', ')
          render :new
        end
        format.json { render json: { success: false, errors: @uploaded_file.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end
end
