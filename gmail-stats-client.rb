#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'applix'

Defaults = {
  :host => '127.0.0.1', :port => 2013, 
}

# args: login, options: host, port
#
def main args, options = {}
  options = (Defaults.merge options)
  sock = TCPSocket.open options[:host], options[:port]
  sock.puts(args.join ' ')
  result = sock.gets.strip
  puts "result: #{result}"

  if db_path = options[:db]
    db = (File.open(db_path) { |fd| YAML.load fd }) rescue []
    (db << result).sort!
    File.open(db_path, "w") { |fd| fd.write db.to_yaml }
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

