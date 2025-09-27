class HomeController < ApplicationController
  def index
  end

  def validation
  redirect_to new_upload_path, alert: 'Функціонал перевірки ще не реалізовано'
end

def split
  redirect_to new_upload_path, alert: 'Функціонал поділу файлу ще не реалізовано'
end
end
