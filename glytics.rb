#!/usr/bin/env ruby

require 'rubygems'
require 'date'
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
    session = (Session.new @username, @password)
    yield session
  ensure
    session.logout rescue nil
  end

  def report 
    (Reports.new self)
  end

  class Session < Net::IMAP

    def initialize username, password
      super('imap.gmail.com', '993', true)
      login username, password
    end

    # returns mail UID list
    def mails_in_folder_in_date_range folder, start_date, end_date
      examine folder
      t1 = start_date.strftime('%e-%b-%Y')
      t2 = (end_date + 1).strftime('%e-%b-%Y')
      uids = uid_search ['BEFORE', t2, 'SINCE', t1]
    end

    # returns mail UID list
    def mails_in_folder_on_given_date folder, date
      examine folder
      uids = uid_search ['ON', date.strftime('%e-%b-%Y')]
      #puts "#{uids.size} mails in #{folder} on #{date_s}"
    end

    # returns mail UID list
    def mails_in_folder_before_given_date folder, date
      examine folder
      uids = uid_search ['BEFORE', date.strftime('%e-%b-%Y')]
      #puts "#{uids.size} mails in #{folder} on #{date_s}"
    end

    # return list of Gmail folders
    def folders
      list '', '[Gmail]/%'
    end

    # examine folder 
    def in_folder name
      examine(@folder_name = name)
      self
    end
    def in_trash    
      in_folder('[Gmail]/Trash') 
    end
    def in_sent
      in_folder('[Gmail]/Sent Mail') 
    end
    def in_archived
      in_folder('[Gmail]/All Mail') 
    end
    def in_starred
      in_folder('[Gmail]/Starred') 
    end

    def imap_date string_or_date
      unless (string_or_date.is_a? Date)
        string_or_date = (Date.parse string_or_date) 
      end
      string_or_date.strftime('%e-%b-%Y')
    end
      
    def on_given_date date
      uid_search ['ON', imap_date(date)]
    end

    # returns UID list, including first day, excluding last day
    def in_period first_day, last_day
      #t1 = first_day
      #t2 = (Date.parse(last_day) + 1)
      # BEFORE <date>: messages with an internal date strictly before <date>
      # SINCE <date>: messages with an internal date on or after <date>
      uid_search ['BEFORE', imap_date(last_day), 'SINCE', imap_date(first_day)]
    end

    def before date, including_date = true
      if including_date
        date = Date.parse(date) + 1
      end
      uid_search ['BEFORE', imap_date(date)]
    end
  end

  class Reports
    def initialize gmail
      @gmail = gmail
    end

    # time period including first and last day
    def in_period first_day, last_day, _ = {}
      @gmail.session do |session|
        {
          :name => :in_period, 
          :first_day => first_day,
          :last_day => last_day, 
          :trashed  => session.in_trash.in_period(first_day, last_day).size,
          :sent     => session.in_sent.in_period(first_day, last_day).size,
          :archived => session.in_archived.in_period(first_day, last_day).size,
          :starred  => session.in_starred.before(last_day).size,
        }
      end
    end

    def on_date date, _ = {}
      @gmail.session do |session|
        {
          :name     => :on_date, :date => date,
          :trashed  => session.in_trash.on_given_date(date).size,
          :sent     => session.in_sent.on_given_date(date).size,
          :archived => session.in_archived.on_given_date(date).size,
          :starred  => session.in_starred.before(date).size,
        }
      end
    end

    def yesterday _ = {}
      on_date (Date.today - 1).strftime('%e-%b-%Y')
    end
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
  end

  def serve sock, options
    while request = sock.gets
      args = request.strip.split /\s+/
      puts "request: #{args.inspect}"
      report = args.shift
      result = @gmail.report.send(report, *args, options)
      #puts ":#{report}: #{result.inspect}"
      sock.puts(result.inspect)
      sock.puts '' rescue nil
    end
  end
end

Defaults = {
  #:date => (Date.today - 1).strftime('%e-%b-%Y'), # yesterday
  :interface => '127.0.0.1', :port => 2013, 
}

Applix.main(ARGV, Defaults) do 
  prolog do |args, options|
    # account is an command line arg but password is prompted, never have that
    # in a config or on the command line!
    @password = ask('enter password: ') {|q| q.echo = '*'}

    (username = args.shift) or raise 'no username?'
    @gmail = Gmail.new(username, @password)
  end

  handle(:server) do |*_, options|
    daemon = MboxDaemon.new(@gmail)
    daemon.run options
  end

  handle(:report) do |*args, options|
    puts "report: #{args.inspect}, #{options.inspect}"
    report = args.shift
    result = @gmail.report.send(report, *args, options)
    puts ":#{report}: #{result.inspect}"
  end

  any do |*args, options|
    puts "any: #{args.inspect}, #{options.inspect}"
    report = args.shift
    result = @gmail.report.send(report, *args, options)
    puts ":#{report}: #{result.inspect}"
  end

  epilog do |rc, args, options|
    # hmmm, generalizing the reporting down here?
  end
end

__END__

  def serve_ sock, options
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

class MboxQueries 
  def initialize session
    @session = session
  end

  def number_of_deleted_mails t1, t2 = nil
    (@session.mails_in_folder_on_given_date '[Gmail]/Trash', t1, t2).size
  end

  def number_of_sent_mails t1, t2 = nil
    (@session.mails_in_folder_on_given_date '[Gmail]/Sent Mail', t1, t2).size
  end

  def number_of_archived_mails t1, t2 = nil
    (@session.mails_in_folder_on_given_date '[Gmail]/All Mail', t1, t2).size
  end

  def total_number_of_starred_mails on_date
    (@session.mails_in_folder_before_given_date '[Gmail]/Starred', on_date+1).size
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
      (@session.in_trash { on_given_date date }).size,
      (@session.in_sent { on_given_date date }).size,
      (@session.in_archived { on_given_date date }).size,
      (@session.in_starred { before_given_date date+1 }).size,
    ]
  end
end
