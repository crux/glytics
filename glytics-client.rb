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
    #
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
    @days ||= self[:on_date].values.sort {|a, b| a["date"] <=> b["date"]}
  end

  def weeks
    @weeks ||= group_by_weeks(days).values.sort {|a,b| a['date']<=>b['date']}
  end

  def group_by_weeks days
    weeks = days.inject({}) do |weeks, record|
      cweek = Date.parse(record["date"]).cweek
      week = (weeks[cweek] ||= Hash.new {|h,k| h['cweek'] = cweek})
      week['date'] = record['date']
      week['trashed'] += record['trashed']
      week['sent'] +=  record['sent']
      week['archived'] += record['archived']
      week['starred'] = record['starred']
      weeks
    end
    #puts "weeks: #{weeks.inspect}"
    weeks
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
    :line_colors => '4a8c3d,cbd64d,dfc613,cccccc',
  }

  def initialize options = {}
    @options = (Defaults.merge options)
    @model = Model.new @options[:modelfile]
  end

  def show 
    # XXX: mac osx only!
    system "open #{@options[:filename]}"
  end
  
  def daily args, options = {}
    options = (@options.merge options)

    # render to file when filename is given
    (not options[:filename].nil?) and (options[:format] = 'file')

    keys = %w(sent archived starred trashed)
    dates, sent, archived, starred, trashed = (["date"] + keys).map do |key| 
      @model.days.map { |record| record[key] }
    end

    x_label = dates.each_with_index.map {|x,idx| x if idx % 90 == 0}.compact
    x_label << dates.last
    puts "x_label: #{x_label}"

    options.update(
      :data => [sent, archived, starred, trashed],
      :legend => keys,
      :title => 'mails (daily)',
      :axis_with_labels => ['x', 'y'], # 'date', '# of mails'],
      :axis_labels => [x_label],
    )
    #puts "options: #{options.inspect}"

    chart = Gchart.line(options)
    puts chart
  end

  def weekly args, options = {}
    options = (@options.merge options)

    # render to file when filename is given
    (not options[:filename].nil?) and (options[:format] = 'file')

    keys = %w(sent archived starred trashed)
    cweeks, sent, archived, starred, trashed = (['cweek'] + keys).map do |key| 
      @model.weeks.map { |record| record[key] }
    end

    n = (cweeks.size.to_f / 4).round
    x_label = cweeks.each_with_index.map {|x,idx| x if idx % n == 0}.compact
    x_label << cweeks.last
    #puts "x_label: #{x_label}"

    options.update(
      :legend => keys,
      :title => 'mails (weekly)',
      :axis_with_labels => ['x', 'y', 'r', 't'], # 'date', '# of mails'],
      :axis_labels => [x_label],
    )
    puts "options: #{options.inspect}"

    # inject data AFTER we dumped options to stdout
    options.update(:data => [sent, archived, starred, trashed])

    chart = Gchart.line(options)
    puts chart
  end
end

Applix.main(ARGV, Defaults) do 

  cluster(:render) do
    prolog do |_, options|
      @cm = ChartMaker.new options
    end

    handle(:daily) do |*args, options|
      @cm.daily args, options
    end

    handle(:weekly) do |*args, options|
      @cm.weekly args, options
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

