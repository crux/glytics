#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'glytics'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 

  cluster(:render) do
    prolog do |_, options|
      @cm = GoogleChartMaker.new options
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

