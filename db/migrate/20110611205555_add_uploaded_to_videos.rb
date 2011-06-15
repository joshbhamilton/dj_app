class AddUploadedToVideos < ActiveRecord::Migration
  def self.up
    add_column :videos, :uploaded, :boolean
  end

  def self.down
    remove_column :videos, :uploaded
  end
end
