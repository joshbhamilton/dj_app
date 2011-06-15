class VideoWorker < Struct.new(:video_id)  
  def perform
    video = Video.find(video_id, :conditions => {:encoded => false})
    if video
      if File.extname(video.file_name) == '.wma'
        video.encode
      else
        video.encoded = true
        video.save!
      end
    end
  end
end
