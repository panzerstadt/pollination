# TODO: put this into a gem file


# Install the following gems
# gem install uuid

require 'fileutils'
require 'thread'
require 'uuid'
require 'pp'

NUMBER_OF_PROCESSORS = 8

class Droneify
  def initialize(grasshopper_definition)
    @grasshopper_definition = grasshopper_definition
    # create a hash to track which processor is being used

    @processor_tracker = {}
    NUMBER_OF_PROCESSORS.times do |processor|
      @processor_tracker[processor] = false

    end
  end


  def tracker_jacker(json_file, processor_id, destination_directory, &block)
    pp "running #{json_file}"
    json_dir = File.dirname(json_file)

    random = UUID.new.generate
    dest_dir = "#{destination_directory}/job_#{random}"
    FileUtils.mkdir_p(dest_dir)
    FileUtils.copy(json_file, "#{dest_dir}/ParamSet.json")

    # Also copy to the run directory
    run_dir = "#{File.dirname(__FILE__)}/Run/Processor_#{processor_id}"
    fail "Run dir missing #{run_dir}" unless File.exist? run_dir

    FileUtils.copy(json_file, "#{run_dir}/ParamSet.json")

    faux_wait = 1
    receipt_file = "#{run_dir}/done.receipt"
    until File.exist?(receipt_file) # || timeout !
      faux_wait += 1

      if faux_wait >= 10
        File.open(receipt_file, 'w') { |f| f << "#{Time.now}" }
      end
      sleep 1
    end

    # Move the results out of the run directorys
    results = Dir["#{run_dir}/*"]
    results.each do |r|
      FileUtils.move(r, "#{destination_directory}/#{File.basename(r)}") unless File.basename(r) == 'DefMaster.gh'
    end
  end

  # chunk up all of the files and put them into their own directory
  def swarm(json_file_directory, destination_directory)
    queue = Queue.new
    threads = []

    # Create the run directories (1 per core and populate with the GH file)
    @processor_tracker.each do |k,_|
      # Force removal of the directory if there
      d = "#{File.dirname(__FILE__)}/Run/Processor_#{k}"
      FileUtils.rm_rf d
      FileUtils.mkdir_p d

      # stage the grasshopper file
      unless File.exist? "#{d}/#{File.basename(@grasshopper_definition)}"
        FileUtils.copy @grasshopper_definition, "#{d}/#{File.basename(@grasshopper_definition)}"
      end
    end

    FileUtils.rm_rf(destination_directory)
    # add the jsons to the queue to process
    queue = Dir["#{json_file_directory}/*.json"]

    puts "Queue to run is:"
    puts queue
    NUMBER_OF_PROCESSORS.times do
      threads << Thread.new do
        until queue.empty?
          bee = queue.pop #(true)
          if bee
            processor_id = get_available_processor
            @processor_tracker[processor_id] = true
            tracker_jacker(bee, processor_id, destination_directory)
            @processor_tracker[processor_id] = false
          end
        end

        # TODO: what next?
        puts "Done"
      end
    end

    threads.each { |t| t.join }
  end

  private

  def get_available_processor
    @processor_tracker.find{ | k, v| v == false}.first
  end

end


# this is cheeze... but putting the script call here
drone = Droneify.new("#{File.dirname(__FILE__)}/DefMaster.gh")
drone.swarm("#{File.dirname(__FILE__)}/Instances", "#{File.dirname(__FILE__)}/Swarm")

