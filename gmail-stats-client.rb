#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 

  any do |*args, options|

    records = {}
    if (datafile = options[:db]) and (File.exists? datafile)
      samples = (File.open(datafile) { |fd| YAML.load fd })
      samples.each do |sample|
        date = (sample.split ':').first
        records[date] = sample
      end
    end

    request = args.join ' '
    puts "request: #{request}"
    sock = TCPSocket.open options[:host], options[:port]
    sock.puts(request)
    loop do
      result = sock.gets.strip
      break if result.empty?
      puts "result: #{result}"
      date = (result.split ':').first
      records[date] = result
    end
    puts 'done.'

    if datafile
      values = records.values.sort
      File.open(datafile, "w") { |fd| fd.write values.to_yaml }
    end
  end
end

__END__

# args: login, options: host, port
#
def main args, options = {}
  options = (Defaults.merge options)
  sock = TCPSocket.open options[:host], options[:port]

  records = {}
  if (datafile = options[:db]) and (File.exists? datafile)
    samples = (File.open(datafile) { |fd| YAML.load fd })
    samples.each do |sample|
      date = (sample.split ':').first
      records[date] = sample
    end
  end

  request = args.join ' '
  puts "request: #{request}"
  sock.puts(request)
  loop do
    result = sock.gets.strip
    break if result.empty?
    puts "result: #{result}"
    date = (result.split ':').first
    records[date] = result
  end
  puts 'done.'

  if datafile
    values = records.values.sort
    File.open(datafile, "w") { |fd| fd.write values.to_yaml }
  end
end

params = Hash.from_argv ARGV
begin 
  main params[:args], params
rescue => e
  puts <<-EOT

## #{e}

usage: #{__FILE__} <task> <username>

--- #{e.backtrace.join "\n    "}
  EOT
end
