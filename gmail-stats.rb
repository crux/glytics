#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'net/imap'
require 'highline/import'
require 'applix'

def get_password prompt = 'enter password: '
  ask(prompt) {|q| q.echo = '*'}
end

Defaults = {
  :date => (Date.today - 1).strftime('%e-%b-%Y'), # yesterday
}

class M < Net::IMAP
  def initialize username, password
    super 'imap.gmail.com', '993', true
    @username, @password = username, password
    login username, password
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
end

def dump_fetch_data fd
  #msg = fd.attr['RFC822']
  #puts "-->#{fd.attr['RFC822']}<--"
  #puts "-#{fd} :: #{fd.attr['UID']}-"
  puts "- #{fd.attr['UID']} -"
  e = fd.attr['ENVELOPE']
  puts "subject:     #{e.subject}"
  puts "from:        #{e.from.first}"
  return 
    
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
  #sender:      #{[:name, :route, :mailbox, :host].map {|x| e.sender.send x}}
    #yield data 
end


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

# args: login, options: date
#
def main args, options = {}

  login = args.shift

  options = (Defaults.merge options)
  date = Date.parse(options[:date])

  # password is prompted, never have that in a config or on the command line!
  password = get_password

  mbox = M.new login, password
  puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"

  # number of deleted mails
  mail_uids = mbox.mails_in_folder_on_given_date '[Gmail]/Trash', date
  puts "number of deleted mails: #{mail_uids.size}"

  # number of sent mails
  mail_uids = mbox.mails_in_folder_on_given_date '[Gmail]/Sent Mail', date
  puts "number of sent mails: #{mail_uids.size}"

  # number of archived mails
  mail_uids = mbox.mails_in_folder_on_given_date '[Gmail]/All Mail', date
  puts "number of archived mails: #{mail_uids.size}"

  # total number of starred mails
  mail_uids = mbox.mails_in_folder_before_given_date('[Gmail]/Starred', date+1)
  puts "total number of starred mails: #{mail_uids.size}"
end

params = Hash.from_argv ARGV
main params[:args], params

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
