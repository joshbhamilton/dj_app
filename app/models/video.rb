class Video < ActiveRecord::Base
  def encode
    logger.info "Encoding #{self.file_name}..."
    sleep_time = rand(60)
    sleep(sleep_time)
    self.encoded = true
    self.save!
    logger.info "Finished encoding #{self.file_name} in #{sleep_time}."
  end
  
  def upload
    logger.info "Uploading #{self.file_name}..."
    sleep_time = rand(60)
    sleep(sleep_time)
    self.uploaded = true
    self.save!
    logger.info "Finished uploading #{self.file_name} in #{sleep_time}"
  end
  handle_asynchronously :upload, :run_at => Proc.new {5.minutes.from_now}
end
