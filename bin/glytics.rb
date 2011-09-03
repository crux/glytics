#!/usr/bin/env ruby

require 'rubygems'
require 'date'
require 'net/imap'
require 'json'
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
      #unless (string_or_date.is_a? Date)
      #  string_or_date = (Date.parse string_or_date) 
      #end
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

    def before date #, including_date = true
      #if including_date
      #  date = Date.parse(date) + 1
      #end
      uid_search ['BEFORE', imap_date(date)]
    end
  end

  class Reports
    def initialize gmail
      @gmail = gmail
    end

    def typed_date date
      (date.is_a? Date) && date || (Date.parse date)
    end

    # time period including first and last day
    def in_period first_day, last_day, _ = {}
      first_day = (typed_date first_day)
      last_day = (typed_date last_day)
      @gmail.session do |session|
        {
          :name => :in_period, 
          :first_day => first_day,
          :last_day => last_day, 
          :trashed  => session.in_trash.in_period(first_day, last_day).size,
          :sent     => session.in_sent.in_period(first_day, last_day).size,
          :archived => session.in_archived.in_period(first_day, last_day).size,
          :starred  => session.in_starred.before(last_day+1).size,
        }
      end
    end

    def on_date date, _ = {}
      date = (typed_date date)
      @gmail.session do |session|
        {
          :name     => :on_date, :date => date,
          :trashed  => session.in_trash.on_given_date(date).size,
          :sent     => session.in_sent.on_given_date(date).size,
          :archived => session.in_archived.on_given_date(date).size,
          :starred  => session.in_starred.before(date+1).size,
        }
      end
    end

    def yesterday _ = {}
      on_date(Date.today - 1)
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
        puts 'closing session...'
        sock.close rescue nil
        server.close rescue nil
        puts 'done.'
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
      sock.puts(result.to_json)
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
    @daemon = MboxDaemon.new(@gmail)
    @daemon.run options
  end

  handle(:report) do |*args, options|
    puts "report: #{args.inspect}, #{options.inspect}"
    report = args.shift
    @result = @gmail.report.send(report, *args, options)
    puts ":#{report}: #{@result.inspect}"
  end

  any do |*args, options|
    #puts "any: #{args.inspect}, #{options.inspect}"
    @report = args.shift
    @result = @gmail.report.send(@report, *args, options)
    #puts ":#{report}: #{@result.inspect}"
  end

  epilog do |rc, args, options|
    if @result
      puts " -- #{@report} --"
      keys = @result.keys.sort
      maxcolumns = keys.max.length
      keys.each do |key|
        #puts "#{key}: #{@result[key]}"
        print("%#{maxcolumns+2}s : #{@result[key]}\n" % [key])
      end
    end
  end
end
