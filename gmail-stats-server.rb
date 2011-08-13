#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'net/imap'
require 'socket'
require 'highline/import'
require 'applix'

def prompt_for_password prompt = 'enter password: '
  ask(prompt) {|q| q.echo = '*'}
end

Defaults = {
  :date => (Date.today - 1).strftime('%e-%b-%Y'), # yesterday
  :interface => '127.0.0.1', :port => 2013, 
}

class Gmail
  def initialize username, password
    #super 'imap.gmail.com', '993', true
    @username, @password = username, password
  end

  # yields IMAP session object into block and returnsblock result
  def session &blk
    @session and (raise 'concurrent sessions not allowed')
    @session = (Net::IMAP.new 'imap.gmail.com', '993', true)
    @session.login @username, @password
    yield self
  ensure
    @session = nil
    #logout rescue nil
  end

  def folders
    @session.list '', '[Gmail]/%'
  end

  # returns mail UID list
  def mails_in_folder_on_given_date folder, date
    @session.examine folder
    #condition = (date.nil? && ['all'] || ['ON', date.strftime '%e-%b-%Y']
    uids = @session.uid_search ['ON', date.strftime('%e-%b-%Y')]
    #puts "#{uids.size} mails in #{folder} on #{date_s}"
  end

  # returns mail UID list
  def mails_in_folder_before_given_date folder, date
    @session.examine folder
    uids = @session.uid_search ['BEFORE', date.strftime('%e-%b-%Y')]
    #puts "#{uids.size} mails in #{folder} on #{date_s}"
  end
end

class MboxQueries 
  def initialize mbox
    @mbox = mbox
  end

  def number_of_deleted_mails on_date
    (@mbox.mails_in_folder_on_given_date '[Gmail]/Trash', on_date).size
  end

  def number_of_sent_mails on_date
    (@mbox.mails_in_folder_on_given_date '[Gmail]/Sent Mail', on_date).size
  end

  def number_of_archived_mails on_date
    (@mbox.mails_in_folder_on_given_date '[Gmail]/All Mail', on_date).size
  end

  def total_number_of_starred_mails before_date
    (@mbox.mails_in_folder_before_given_date '[Gmail]/Starred', before_date).size
  end
end

class MboxDaemon
  def initialize gmail
    @gmail = gmail
  end

  def run options
    puts "gmail stats server.."
    loop do # Servers run forever
      server = TCPServer.new(options[:interface], options[:port])  
      sock = server.accept # one client at a time
      puts " -- #{Time.now} accept: #{sock.addr}" 
      begin
        (serve sock, options)
      rescue => e
        puts " ## #{e} ##\n    #{e.backtrace.join "\n    "}"
      ensure
        sock.close rescue nil
        puts "session closed"
        server.close rescue nil
      end
    end
  ensure
  end

  def serve sock, options
    while request = sock.gets
      request = request.strip.split /\s+/
      puts "request: #{request.inspect}"
      case request.shift
      when /on_date$/
        options[:date] = Date.parse(request.first)
        report sock, options
      when /on_date_range/
        options[:from_date] = Date.parse(request.shift)
        options[:to_date] = Date.parse(request.shift)
        report_range sock, options
      when /yesterday/
        report sock, options
      else 
        raise "400 bad request: #{request}"
      end
      sock.puts '' rescue nil
    end
  end

  def report sock, options
    #headers = "HTTP/1.1 200 OK\r\nServer: Ruby\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n"
    #sock.puts headers  # Send the time to the sock
    #puts ">>>> #{headers}"
    date = options[:date]
    values = @gmail.session do |gmail|
        q = MboxQueries.new(gmail)
        [ 
          date,
          (q.number_of_deleted_mails date),
          (q.number_of_sent_mails date),
          (q.number_of_archived_mails date),
          (q.total_number_of_starred_mails date+1)
        ]
    end
    sock.puts(values.join ':')
    #puts ">>>> #{values.join ':'}"
  end

  def report_range sock, options
    date = options[:from_date]
    while date < options[:to_date]
      puts "on_date: #{date.strftime('%e-%b-%Y')}"
      options[:date] = date
      report sock, options
      date += 1
    end
  end
end

def server username, password, options 
  daemon = MboxDaemon.new(Gmail.new username, password)
  daemon.run options
end

def report username, password, options 
  #puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"
  (Gmail.new username, password).session do |gmail|
    q = MboxQueries.new gmail
    date = options[:date]
    puts <<-EOR
 -- mails stats for #{date}
       deleted: #{q.number_of_deleted_mails date}
          sent: #{q.number_of_sent_mails date}
      archived: #{q.number_of_archived_mails date}
starred(total): #{q.total_number_of_starred_mails date+1}
    EOR
  end
end

# args: username, options: date
#
def main args, options = {}
  options = (Defaults.merge options)
  options[:date] = Date.parse(options[:date]) # up-type string date

  action = args.shift or raise "no action"

  # account is an command line arg but password is prompted, never have that in
  # a config or on the command line!
  #
  username = args.shift # or raise "no username"
  password = prompt_for_password

  # which method to run depend on first command line argument..
  send action, username, password, options
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

__END__

  #headers = "HTTP/1.1 200 OK\r\nServer: Ruby\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n"
  #client.puts headers  # Send the time to the client
  #puts ">>>> #{headers}"

  def self.fetch_and_dump uids
    attr = %w{UID RFC822 ENVELOPE}
    uid_fetch(uids, attr).each do |fd| 
      #msg = fd.attr['RFC822']
      #puts "-->#{fd.attr['RFC822']}<--"
      #puts "-#{fd} :: #{fd.attr['UID']}-"
      puts "- #{fd.attr['UID']} -"
      e = fd.attr['ENVELOPE']
      puts <<-EOT
message_id:  #{e.message_id}
subject:     #{e.subject}
date:        #{e.date}
from:        #{e.from.first}
sender:      #{e.sender}
reply_to:    #{e.reply_to}
to:          #{e.to}
cc:          #{e.cc}
bcc:         #{e.bcc}
in_reply_to: #{e.in_reply_to}
      EOT
    end
  #sender:      #{[:name, :route, :mailbox, :host].map {|x| e.sender.send x}}
  #yield data 
  end
