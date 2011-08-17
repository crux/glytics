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
  def mails_in_folder_on_given_date folder, start_date, end_date = nil
    @session.examine folder
    if end_date
      t1 = start_date.strftime('%e-%b-%Y')
      t2 = (end_date + 1).strftime('%e-%b-%Y')
      uids = @session.uid_search ['BEFORE', t2, 'SINCE', t1]
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

  def number_of_deleted_mails t1, t2 = nil
    (@mbox.mails_in_folder_on_given_date '[Gmail]/Trash', t1, t2).size
  end

  def number_of_sent_mails t1, t2 = nil
    (@mbox.mails_in_folder_on_given_date '[Gmail]/Sent Mail', t1, t2).size
  end

  def number_of_archived_mails t1, t2 = nil
    (@mbox.mails_in_folder_on_given_date '[Gmail]/All Mail', t1, t2).size
  end

  def total_number_of_starred_mails on_date
    (@mbox.mails_in_folder_before_given_date '[Gmail]/Starred', on_date+1).size
  end

  def report_range from_date, to_date
    [
      from_date, to_date,
      (number_of_deleted_mails from_date, to_date),
      (number_of_sent_mails from_date, to_date),
      (number_of_archived_mails from_date, to_date),
      (total_number_of_starred_mails to_date)
    ]
  end

  def report_on_date date
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
      when /in_range/
        options[:from_date] = Date.parse(request.shift)
        options[:to_date] = Date.parse(request.shift)
        report_range sock, options
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
      MboxQueries.new(gmail).report_on_date date
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
  prolog do |args, options|
    # account is an command line arg but password is prompted, never have that
    # in a config or on the command line!
    @password = ask('enter password: ') {|q| q.echo = '*'}

    (username = args.shift) or raise 'no username?'
    @gmail = Gmail.new(username, @password)

    # needs to up-type string date because it could come from command line
    options[:date] = Date.parse(options[:date])
  end

  handle(:server) do |options|
    daemon = MboxDaemon.new(@gmail)
    daemon.run options
  end

  handle(:report) do |options|
    #puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"
    @gmail.session do |gmail|
      date = options[:date]
      values = MboxQueries.new(gmail).report_on_date(date)
      puts <<-EOR
 -- mails stats for #{values[0]}
       deleted: #{values[1]}
          sent: #{values[2]}
      archived: #{values[3]}
starred(total): #{values[4]}
      EOR
    end
  end

  handle(:date_range) do |from_date, to_date, options|
    # begin and end of date range
    from_date = Date.parse(from_date)
    to_date = Date.parse(to_date)
    @gmail.session do |gmail|
      values = MboxQueries.new(gmail).report_range(from_date, to_date)
      puts <<-EOR
 -- mails stats for #{values[0]} - #{values[1]}
       deleted: #{values[2]}
          sent: #{values[3]}
      archived: #{values[4]}
starred(total): #{values[5]}
      EOR
    end
  end
end
