# putting a model class over the code for post-processing and persisting the
# query results
class Model < Hash

  def initialize filename
    @filename = filename

    if File.exists? @filename
      h = (File.open(@filename) { |fd| YAML.load fd })
      self.replace h
    end
  end

  def days
    #
    # thats what an :on_date entry looks like:
    #
    #  "2011-08-24": 
    #    name: on_date
    #    date: "2011-08-24"
    #    trashed: 167
    #    sent: 8
    #    archived: 35
    #    starred: 13
    #
    @days ||= self[:on_date].values.sort {|a, b| a["date"] <=> b["date"]}
  end

  def weeks
    @weeks ||= group_by_weeks(days).values.sort {|a,b| a['date']<=>b['date']}
  end

  def group_by_weeks days
    weeks = days.inject({}) do |weeks, record|
      cweek = Date.parse(record["date"]).cweek
      week = (weeks[cweek] ||= Hash.new {|h,k| h['cweek'] = cweek})
      week['date'] = record['date']
      week['trashed'] += record['trashed']
      week['sent'] +=  record['sent']
      week['archived'] += record['archived']
      week['starred'] = record['starred']
      weeks
    end
    #puts "weeks: #{weeks.inspect}"
    weeks
  end

  def save
    File.open(@filename, "w") {|fd| fd.write self.to_yaml}
  end
  def save_as filename
    @filename = filename
    save
  end

  def insert record
    record_type = record["name"]
    m = "insert_#{record_type}_record"
    self.send(m, record)
  end

  def insert_on_date_record record
    date = record['date']
    (self[:on_date] ||= {})[date] = record
  end

  # example: {"name":"in_period","first_day":"2010-01-01","last_day":"2011-01-01","trashed":4,"sent":2313,"archived":20346,"starred":4}
  #
  def insert_in_period_record record
    puts <<-EOT

 !! in_period records are considered being ad-hoc queries and therefore are not
 !! being persisted:"

#{record.inspect}"

    EOT
  end
end
