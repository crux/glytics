#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'socket'
require 'applix'

Defaults = {
  :host => 'sebrink.de', :port => 2013, 
}

# args: login, options: host, port
#
def main args, options = {}
  options = (Defaults.merge options)
  sock = TCPSocket.open options[:host], options[:port]
  sock.puts(args.join ' ')
  result = sock.gets.strip
  puts "result: #{result}"
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

