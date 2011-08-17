#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 

  prolog do |*args, options|
    @records = {}
    if (@datafile = options[:db]) and (File.exists? @datafile)
      samples = (File.open(@datafile) { |fd| YAML.load fd })
      samples.each do |sample|
        date = (sample.split ':').first
        @records[date] = sample
      end
    end
  end

  any do |*args, options|
    request = args.join ' '
    puts "request: #{request}"
    sock = TCPSocket.open options[:host], options[:port]
    sock.puts(request)
    loop do
      result = sock.gets.strip
      break if result.empty?
      puts "result: #{result}"
      date = (result.split ':').first
      @records[date] = result
    end
    puts 'done.'
  end

  epilog do
    if @datafile
      values = @records.values.sort
      File.open(@datafile, "w") { |fd| fd.write values.to_yaml }
    end
  end
end
