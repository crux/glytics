#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'net/imap'
require 'socket'
require 'highline/import'
require 'applix'

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
  def _mails_in_folder_on_given_date folder, date
    @session.examine folder
    #condition = (date.nil? && ['all'] || ['ON', date.strftime '%e-%b-%Y']
    uids = @session.uid_search ['ON', date.strftime('%e-%b-%Y')]
    #puts "#{uids.size} mails in #{folder} on #{date_s}"
  end
  def mails_in_folder_on_given_date folder, start_date, end_date = nil
    @session.examine folder
    if end_date
      t0 = (start_date - 1).strftime('%e-%b-%Y')
      t1 = end_date.strftime('%e-%b-%Y')
      uids = @session.uid_search ['AFTER', t0, 'BEFORE', t1]
    else
      date = start_date
      uids = @session.uid_search ['ON', date.strftime('%e-%b-%Y')]
    end
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

  def total_number_of_starred_mails on_date
    (@mbox.mails_in_folder_before_given_date '[Gmail]/Starred', on_date+1).size
  end

  def report_on_date date, options
    [
      date,
      (number_of_deleted_mails date),
      (number_of_sent_mails date),
      (number_of_archived_mails date),
      (total_number_of_starred_mails date)
    ]
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
      puts " -- #{Time.now}\naccept: #{sock.addr}" 
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
      when /on_date_sequence/
        options[:from_date] = Date.parse(request.shift)
        options[:to_date] = Date.parse(request.shift)
        report_sequence sock, options
      when /yesterday/
        report sock, options
      else 
        raise "400 bad request: #{request}"
      end
      sock.puts '' rescue nil
    end
  end

  def report sock, options
    date = options[:date]
    values = @gmail.session do |gmail| 
      MboxQueries.new(gmail).report_on_date date, options 
    end
    sock.puts(values.join ':')
  end
    
  def report_sequence sock, options
    date = options[:from_date]
    while date < options[:to_date]
      puts "on_date: #{date.strftime('%e-%b-%Y')}"
      options[:date] = date
      report sock, options
      date += 1
    end
  end
end

Defaults = {
  :date => (Date.today - 1).strftime('%e-%b-%Y'), # yesterday
  :interface => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 
  prolog do |*_, options|
    # account is an command line arg but password is prompted, never have that
    # in a config or on the command line!
    @password = ask('enter password: ') {|q| q.echo = '*'}

    # needs to up-type string date because it could come from command line
    options[:date] = Date.parse(options[:date])
  end

  handle(:server) do |username, options|
    daemon = MboxDaemon.new(Gmail.new username, @password)
    daemon.run options
  end

  handle(:report) do |username, options|
    #puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"
    (Gmail.new username, @password).session do |gmail|
      q = MboxQueries.new gmail
      date = options[:date]
      puts <<-EOR
 -- mails stats for #{date}
       deleted: #{q.number_of_deleted_mails date}
          sent: #{q.number_of_sent_mails date}
      archived: #{q.number_of_archived_mails date}
starred(total): #{q.total_number_of_starred_mails date}
    EOR
    end
  end
end
