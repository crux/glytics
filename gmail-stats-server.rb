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

class Mbox < Net::IMAP
  def initialize username, password
    super 'imap.gmail.com', '993', true
    @username, @password = username, password
    login username, password
  end

  def queries
    @queries ||= MboxQueries.new self
  end

  def folders
    @folders = self.list '', '[Gmail]/%'
  end

  # returns mail UID list
  def mails_in_folder_on_given_date folder, date
    examine folder
    #condition = (date.nil? && ['all'] || ['ON', date.strftime '%e-%b-%Y']
    uids = uid_search ['ON', date.strftime('%e-%b-%Y')]
    #puts "#{uids.size} mails in #{folder} on #{date_s}"
  end

  def mails_in_folder_before_given_date folder, date
    examine folder
    uids = uid_search ['BEFORE', date.strftime('%e-%b-%Y')]
    #puts "#{uids.size} mails in #{folder} on #{date_s}"
  end

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
end

def report login, password, options 
  mbox = Mbox.new login, password
  #puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"

  q = MboxQueries.new mbox

  date = options[:date]
  puts <<-EOR
 -- mails stats for #{date}
       deleted: #{q.number_of_deleted_mails date}
          sent: #{q.number_of_sent_mails date}
      archived: #{q.number_of_archived_mails date}
starred(total): #{q.total_number_of_starred_mails date+1}
  EOR
end

class MboxDaemon 

  def initialize mbox
    @mbox = mbox
    @queries = @mbox.queries
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
    values = [
      date,
      (@queries.number_of_deleted_mails date),
      (@queries.number_of_sent_mails date),
      (@queries.number_of_archived_mails date),
      (@queries.total_number_of_starred_mails date+1)
    ]
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

def server login, password, options 
  mbox = Mbox.new login, password
  daemon = MboxDaemon.new mbox
  daemon.run options
end

# args: login, options: date
#
def main args, options = {}
  options = (Defaults.merge options)
  options[:date] = Date.parse(options[:date]) # up-type string date

  action = args.shift or raise "no action"

  # account is an command line arg but password is prompted, never have that in
  # a config or on the command line!
  #
  login = args.shift # or raise "no username"
  password = prompt_for_password

  # which method to run depend on first command line argument..
  send action, login, password, options
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

=begin
def number_of_mail_in_folder mbox, folder
  mbox.examine folder
  uids = mbox.uid_search ['all']
  puts "#{uids.size} mails in #{folder}"
  uids.size
end

def number_of_mail_in_starred mbox
  number_of_mail_in_folder mbox, folder = '[Gmail]/Starred'
end

def number_of_mails_in_folder_on_given_date mbox, args = {}
  folder = (args[:folder] || '[Gmail]/All Mail')
  date = (args[:date] || (Date.today - 1))

  mbox.examine folder
  date_s = date.strftime "%e-%b-%Y"
  uids = mbox.uid_search(['ON', date_s])
  puts "#{uids.size} mails in #{folder} on #{date_s}"
  uids.size
end

def number_of_mails_sent_yesterday mbox
  number_of_mails_in_folder_on_given_date(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/Sent Mail'
  )
end

def number_of_mails_archived_yesterday mbox
  number_of_mails_in_folder_on_given_date(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/All Mail'
  )
end

def number_of_mails_deleted_yesterday mbox
  number_of_mails_in_folder_on_given_date(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/Trash'
  )
end
=end
__END__
p folders.select { |f| f.name == '[Gmail]' }

mbox.examine 'Sent Messages'
uids = mbox.uid_search(['ON', '19-Jun-2011'])
puts "uid count: #{uids.size}"

imap = Net::IMAP.new 'imap.gmail.com', '993', true
imap.login account[:login], account[:password]

#imap.examine 'INBOX'
imap.examine '[Gmail]/Sent Mail'
# Loop through all messages in the source folder.
#uids = imap.uid_search(['ALL'])zmessenfinan:b 
#uids = imap.uid_search(['NOT', 'DELETED'])
uids = imap.uid_search(['ON', '19-Jun-2011'])
puts "uid count: #{uids.size}"
exit if uids.empty?

attr = %w{UID RFC822 ENVELOPE}
imap.uid_fetch(uids, attr).each { |fd| dump_fetch_data fd }
