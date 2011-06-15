#DJob_App

Sample application to test setting up delayed job.

##Setting DelayedJob up on a Rails 3.0.8 Application

* Added the `delayed_job` gem to my Gemfile. Note: 2.1 only supports Rails 3.0+ - need 2.0 for Rails 2.
* `bundle install`
* If using Active Record,
  `$ script/rails generate delayed_job`
  `$ rake db:migrate`

##Queueing Jobs

    # without delayed_job
    @video.encode
    
    # with delayed_job
    @video.delay.encode
    
If the method should always be run in the background, you can call #handle_asynchronously after the method declaration:

    class Video
      def encode
        logger.info "Encoding #{self.file_name}..."
        sleep_time = rand(60)
        sleep(sleep_time)
        self.encoded = true
        self.save!
        logger.info "Finished encoding #{self.file_name} in #{sleep_time}."
      end
      handle_asynchronously :encode
    end
    
    video = Video.new
    video.encode

`handle_asynchronously` can take the same options that you can send to delay. This includes Proc objects allowing call time evaluation of the value.

QUESTION: Will the webserver/appserver cut this off after a certain time period?

Instead of calling Video#encode in the controller, its better to send a message to the user that work is being processed. Then we can send the task to the background using delayed job.

    #/app/controllers/videos_controller.rb BEFORE
    def create
      @video = Video.new(params[:video])
      if @video.save
        @video.encode
        flash[:notice] = "Video was successfully created"
      else
        render :action => "new"
      end
    end
    

    #/app/controllers/videos_controller.rb AFTER
    def create
      @video = Video.new(params[:video])
      if @video.save
        #
        # Could call with: @video.send_later(:encode). Current way to do it is:
        #
        @video.delay.encode
        msg = 'Video was successfully created.'
        msg << "\nIt is being encoded and will be available shortly."
        flash[:notice] = msg 
        redirect_to(@video)
      else
        render :action => "new"
      end
    end

The `send_later` method takes one argument, the method you are calling in the background on the object that is calling `send_later`. `send_later` creates a new task in the `delayed_jobs` table, with a message saying execute `encode` when the task is run.

## Running Jobs

To process the task, we have two options:

  * `$ rake jobs:work`
  
    This runs in the foreground and provides simple debugging.
    
  * `$ RAILS_ENV=production script/delayed_job -n 2 start`

    This creates two workers in separate processes.

Background processing usually gets problematic. They usually all invoke the Rails environment, causing a lot of memory and CPU to be consumed - and they do it every time the processor fires up.
Delayed Job allows you to start as many instances as you want, on as many boxes as you want. These instances run on an infinite loop - so the Rails environment only loads once and does not keep starting each time a process kicks off.
Delayed Job also offers a very sophisticated locking mechanisms to help ensure that tasks are processed by multiple processes at the same time.

##Custom Workers and Delayed Job

What if we want to perform something more complicated than just calling a method on a class?

For example, what if we only need to encode videos that are uploaded as `.wma`, and not Quicktime videos?

We could add logic in our `encode` method to check the file extension. But Delayed Job also allows us to create custom worker classes that can be added to the queue.
This class must fulfill a simple interface - it must have the `perform` method on it.

    #Our custom VideoWorker class
    class VideoWorker < Struct.new(:video_id)
    #class VideoWorker
      #attr_accessor :video_id
      
      #def initialize(video_id)
      #  self.video_id = video_id
      #end
      
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

Now that we have a custom `VideoWorker`, how do we create a task for DelayedJob to perform?

    #app/controllers/videos_controller.rb
    def create
      @video = Video.new(params[:video])
      if @video.save
        Delayed::Job.enqueue(VideoWorker.new(@video.id))
        msg = 'Video was successfully created.'
        msg << "\nIt is being encoded and will be available shortly."
        flash[:notice] = msg
        redirect_to(@video)
      else
        render :action => "new"
      end
    end
    
So we replaced the `send_later` method with `Delayed::Job.enqueue(VideoWorker.new(@video.id))`
This creates a new instance of the `VideoWorker` class we just built and pass the `@vide.id` to it. Then we call the `enqueue` method on the `Delayed::Job` class and pass it the `VideoWorker` instance we just created. That then creates the task for us in the database.
When the DelayedJob process runs, it executes the `perform` method on our instance of the `VideoWorker` class we created.

QUESTION: Do we have to restart the DelayedJob daemon and/or rake task when we add custom workers?
QUESTION: Where do we add the DelayedJob custom workers?
ANSWER: Added to the lib/ directory - had to change config/application.rb to load this file in.

##Priority

How do we place certain tasks higher than others? We assign it a priority number.
The default priority value is 0. If we pass a second argument to either the `send_later` or `enqueue` method.

    #@video.send_later(:encode, 1)
    @vide.delay encode, 1
    
Because 1 is greater than 0, DelayedJob processes this video first.
When DelayedJob goes to fetch tasks from the delayed_jobs table, it appends the following to the SQL it creates:

    priority DESC, run_at ASC

It first sorts on the priority column, then sorts by the run_at column, getting the oldest records first.

The `run_at` column allows us to tell DelayedJob when to run a particular task.

For example, charging customers on the first of the month. Create a custom worker for this:

    class PaymentWorker < Struct.new(:user_id)
      def perform
        user = User.find(user_id)
        payment_info = user.payment_info
        if payment_info.charge(19.99)
          Postman.deliver_payment_charged_email(user)
          Delayed::Job.enqueue(PaymentWorker.new(user_id), 1000, 1.month.from_now.beginning_of_month)
        else
          Postman.deliver_payment_failure_email(user)
          Delayed::Job.enqueue(PaymentWorker.new(user_id), 2000, 1.day.from_now)
        end
      end
    end

So the third argument is the `run_at` field.

When a customer signs up, we'd add a task to the queue to charge the credit card immediately.

    Delayed::Job.enqueue(PaymentWorker.new(@user.id), 1000)
    
If the task succeeds, it emails the customer notifying them and creates a new task one month from now. If it fails, it emails the customer and then creates a task for the next day.

##Configuring Delayed Job

QUESTION: Is this different now? Different for versions of Rails?

To set our configuration settings, we would create an initializer file, `delayed_job.rb` in the `config/initializers` directory.

    #config/initializers/delayed_job.rb
    Delayed::Job.destroy_failed_jobs = false
    
    silence_warnings do
      Delayed::Job.const_set("MAX_ATTEMPTS", 3)
      Delayed::Job.const_set("MAX_RUN_TIME", 5.minutes)
    end

`Delayed::Job.destroy_failed_jobs = false`
  If a task continues to fail and has hit the maximum number of attempts allotted, DelayedJob purges those tasks from the DB.
  This means you'll lose important info about what is causing these errors and how to fix them.
  By setting this to false, you are telling Delayed Job to keep these tasks around and not delete them - but to stop attempting to process them. This does clutter up the `delayed_jobs` table.
`Delayed::Job.const_set("MAX_ATTEMPTS", 3)`
  The default for this is 25.
  DelayedJob also uses this to determine the wait between each attempt at the task.
  The algorithm for setting the next `run_at` date is: `Time.now + (attempt ** 4) + 5`
  So if the `attempt` variable is at the default 25, the next time would be 100 hours. It'd take 20 full days between first failure and last.
`Delayed::Job.const_set("MAX_RUN_TIME", 5.minutes)`
  The default for this is 4 hours.
  This should be set to the amount of time you think your longest task will take.

In one of your environments, such as `production.rb`, place this:

    #config/environments/production.rb
    config.after_initialize do
      Video.handle_asynchronously :encode
    end

This creates an alias for the `encode` method we created on the `Video` class and sets it up to create a new task whenever you call it.
So when you call `@video.encode`, it is the equivalent of calling `@video.send_later(:encode)`.
The advantage of this is that we don't have to update our code all over the place, because all calls to `encode` method now generate tasks to be run later.

##Deploying Delayed Job

Need to have a way to start/stop/restart the background processes for you when you deploy your application. You MUST restart your DelayedJob processes when you deploy - these processes will still be executing on your old code base, not the new one.

##Deployed on AppCloud - Solo
Just pushed code and deployed. Created couple of tasks. Checked the database to see that they jobs were being created:

    $ mysql -u deploy -pPASSWORD
    mysql> use dj_app;
    mysql> select * from delayed_jobs;

Then needed to process them:
    
    $ cd /data/dj_app/current
    $ RAILS_ENV=production bundle exec rake jobs:work

Validated in the browser that these completed.

Running the rake command is not optimal. Would like to run as a daemon.

##Monitoring Delayed Job

##Problems with Delayed Job

##Using Delayed Job on AppInstance

##Using Delayed Job on UtilityInstance