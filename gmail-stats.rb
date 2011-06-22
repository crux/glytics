#!/usr/bin/env ruby

require 'rubygems'
require 'yaml'
require 'net/imap'
require 'applix'

class M < Net::IMAP
  def initialize username, password
    super 'imap.gmail.com', '993', true
    #@imap = Net::IMAP.new 'imap.gmail.com', '993', true
    @username, @password = username, password
    login username, password
  end

  def folders
    @folders = self.list '', '[Gmail]/%'
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


def number_of_mail_in_starred mbox
  folder = '[Gmail]/Starred'
  mbox.examine folder
  uids = mbox.uid_search ['ALL']
  puts "#{uids.size} mails in #{folder}"
  uids.size
end

def number_mails_on_date_in_folder mbox, args = {}
  folder = (args[:folder] || '[Gmail]/All Mail')
  date = (args[:date] || (Date.today - 1))

  mbox.examine folder
  date_s = date.strftime "%e-%b-%Y"
  uids = mbox.uid_search(['ON', date_s])
  puts "#{uids.size} mails in #{folder} on #{date_s}"
  uids.size
end

def number_of_mails_sent_yesterday mbox
  number_mails_on_date_in_folder(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/Sent Mail'
  )
end

def number_of_mails_archived_yesterday mbox
  number_mails_on_date_in_folder(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/All Mail'
  )
end

def number_of_mails_deleted_yesterday mbox
  number_mails_on_date_in_folder(
    mbox, :date => (Date.today - 1), :folder => '[Gmail]/Trash'
  )
end

# number mails archived yesterday

def main args = []
  c = (YAML.load_file 'accounts.yml') rescue { :account => {} }
  account = c[:account]
  uname, password = *args
  uname && (account[:login] ||= uname)
  password && (account[:password] ||= password)
  puts "account: #{account.inspect}"
  mbox = M.new(account[:login], account[:password])

  puts "folders: #{ mbox.folders.map { |f| f.name }.inspect}"

  #['[Gmail]/All Mail', '[Gmail]/Sent Mail', '[Gmail]/Starred'].each do |folder|
  #  mbox.examine folder
  #  date = (Date.today - 1 ).strftime "%e-%b-%Y"
  #  uids = mbox.uid_search(['ON', date])
  #  puts "#{uids.size} mails in #{folder} on #{date}"
  #end

  number_of_mails_deleted_yesterday mbox
  number_of_mails_sent_yesterday mbox
  number_of_mails_archived_yesterday mbox
  number_of_mail_in_starred mbox
end

main ARGV

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
