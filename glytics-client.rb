#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'json'
require 'socket'
require 'googlecharts'
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

  def days
    @days ||= self[:on_date].values.sort {|a, b| a["date"] <=> b["date"]}
    # thats what an :on_date entry looks like:
    #
    #  "2011-08-24": 
    #    name: on_date
    #    date: "2011-08-24"
    #    trashed: 167
    #    sent: 8
    #    archived: 35
    #    starred: 13
    #
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

class ChartMaker
  Defaults = {
    :modelfile => 'glytics.yml', #:filename => 'chart.png', 
    :format => 'url', # || image_tag || file
    :size => '600x200',
    :line_colors => '4a8c3d,cbd64d,aaaaaa',
  }

  def initialize options = {}
    @options = (Defaults.merge options)
    @model = Model.new @options[:modelfile]
  end

  def show 
    # XXX: mac osx only!
    system "open #{@options[:filename]}"
  end
  
  def days args, options = {}
    options = (@options.merge options)

    # render to file when filename is given
    (not options[:filename].nil?) and (options[:format] = 'file')

    dates, sent, archived, trashed = %w(date sent archived trashed).map do |key| 
      @model.days.map { |record| record[key] }
    end

    x_label = dates.each_with_index.map {|x,idx| x if idx % 30 == 0}.compact
    puts "x_label: #{x_label}"

    options.update(
      :data => [sent, archived, trashed],
      :legend => ['sent', 'archived', 'trashed'],
      :title => 'mails per day', 
      :axis_with_labels => ['x', 'y'], # 'date', '# of mails'],
      #:axis_labels => ['Jan','July','Jan','July','Jan'],
      :axis_labels => [x_label],
    )
    puts "options: #{options.inspect}"

    chart = Gchart.line(options)
    puts chart
  end
end

Applix.main(ARGV, Defaults) do 

  cluster(:render) do
    prolog do |_, options|
      @cm = ChartMaker.new options
    end

    handle(:days) do |*args, options|
      @cm.days args, options
    end

    epilog do |records, *args, options|
      @cm.show if options[:show]
    end
  end

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

  # generic epilog helper method to coordinate Model access
  epilog do |records, *args, options|
    if(datafile = options[:save])
      model = Model.new datafile
      records.each { |record| model.insert record }
      model.save
    end
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

