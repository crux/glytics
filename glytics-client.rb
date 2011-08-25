#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'json'
require 'socket'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

# putting a model class over the code for post-processing and persisting the
# query results
class Model < Hash
  def initialize filename
    @filename = filename

    if File.exists? @filename
      h = (File.open(@filename) { |fd| YAML.load fd })
      self.replace h
    end
  end

  def save
    File.open(@filename, "w") {|fd| fd.write self.to_yaml}
  end
  def save_as filename
    @filename = filename
    save
  end

  def insert record
    record_type = record["name"]
    m = "insert_#{record_type}_record"
    self.send(m, record)
  end

  def insert_on_date_record record
    date = record['date']
    (self[:on_date] ||= {})[date] = record
  end

  # example: {"name":"in_period","first_day":"2010-01-01","last_day":"2011-01-01","trashed":4,"sent":2313,"archived":20346,"starred":4}
  #
  def insert_in_period_record record
    puts <<-EOT

 !! in_period records are considered being ad-hoc queries and therefore are not
 !! being persisted:"

#{record.inspect}"

    EOT
  end
end

Applix.main(ARGV, Defaults) do 

  # :any kind of (non matched) argument is just forwared as request to the
  # glytics daemon. could very well be that this fails,
  #
  any do |*args, options|
    request = args.join ' '
    puts "request: #{request}"
    sock = TCPSocket.open options[:host], options[:port]
    sock.puts(request)
    records = []
    loop do
      response = sock.gets.strip
      break if response.empty?
      puts "response: #{response}"
      records << (JSON.parse response)
    end
    puts 'done.'
    records
  end

  # whatever is returned by a request might be persisted 
  epilog do |records, *args, options|
    if(datafile = options[:db])
      save_model datafile, records, options
    end
  end

  # helper method to coordinate Model access
  def save_model datafile, records, options = {}
    model = Model.new datafile
    records.each { |record| model.insert record }
    model.save
  end
end

__END__

Legacy data file importing code. so i don't need to query that information again

  handle(:port) do |*args, options|
    puts "port: #{args.inspect}"

    filename = args.shift
    records = (File.open(filename) { |fd| YAML.load fd })
    puts "#{records.size} days loaded"
    records.map do |day|
      #- 2011-08-06:24:2:5:23
      day = day.split(/:/)
      {
          "name" =>  "on_date", 
          "date" =>  day[0],
          "trashed" =>  day[1].to_i,
          "sent" =>  day[2].to_i,
          "archived" =>  day[3].to_i,
          "starred" =>  day[4].to_i,
      }
    end
  end

