#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'json'
require 'socket'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 

  any do |*args, options|
    request = args.join ' '
    puts "request: #{request}"
    sock = TCPSocket.open options[:host], options[:port]
    sock.puts(request)
    results = []
    loop do
      result = sock.gets.strip
      break if result.empty?
      puts "result: #{result}"
      results << result
    end
    puts 'done.'
    results
  end

  epilog do |results, *args, options|
    if (@datafile = options[:db])
      model = {}
      if File.exists? @datafile
        model = (File.open(@datafile) { |fd| YAML.load fd })
      end

      results.each do |result|
        record = (JSON.parse result)
        puts "record: #{record.inspect}"
      end

      #values = @records.values.sort
      #File.open(@datafile, "w") { |fd| fd.write values.to_yaml }
    end
  end
end
