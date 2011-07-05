class Book < ActiveRecord::Base
  def combine_for_publishing
    logger.info "Combining for publishing #{self.title}..."
    sleep_time = rand(60)
    sleep(sleep_time)
    self.published = true
    self.save!
    logger.info "Finished encoding #{self.title} in #{sleep_time}."
  end
end
