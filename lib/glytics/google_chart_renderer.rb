require 'googlecharts'

class GoogleChartMaker

  Defaults = {
    :modelfile => 'glytics.yml', #:filename => 'chart.png', 
    :format => 'url', # || image_tag || file
    :size => '600x200',
    :line_colors => '4a8c3d,cbd64d,dfc613,cccccc',
  }

  def initialize options = {}
    @options = (Defaults.merge options)
    @model = Model.new @options[:modelfile]
  end

  def show 
    # XXX: mac osx only!
    system "open #{@options[:filename]}"
  end
  
  def daily args, options = {}
    options = (@options.merge options)

    # render to file when filename is given
    #(not options[:filename].nil?) and (options[:format] = 'file')
    (options[:format] = 'file') if options[:filename]

    keys = %w(sent archived starred trashed)
    dates, sent, archived, starred, trashed = (["date"] + keys).map do |key| 
      @model.days.map { |record| record[key] }
    end

    x_label = dates.each_with_index.map {|x,idx| x if idx % 90 == 0}.compact
    x_label << dates.last
    puts "x_label: #{x_label}"

    options.update(
      :data => [sent, archived, starred, trashed],
      :legend => keys,
      :title => 'mails (daily)',
      :axis_with_labels => ['x', 'y'], # 'date', '# of mails'],
      :axis_labels => [x_label],
    )
    #puts "options: #{options.inspect}"

    chart = Gchart.line(options)
    puts chart
  end

  def weekly args, options = {}
    options = (@options.merge options)

    # render to file when filename is given
    #(not options[:filename].nil?) and (options[:format] = 'file')
    (options[:format] = 'file') if options[:filename]

    keys = %w(sent archived starred trashed)
    cweeks, sent, archived, starred, trashed = (['cweek'] + keys).map do |key| 
      @model.weeks.map { |record| record[key] }
    end

    n = (cweeks.size.to_f / 4).round
    x_label = cweeks.each_with_index.map {|x,idx| x if idx % n == 0}.compact
    x_label << cweeks.last
    #puts "x_label: #{x_label}"

    options.update(
      :legend => keys,
      :title => 'mails (weekly)',
      :axis_with_labels => ['x', 'y', 'r', 't'], # 'date', '# of mails'],
      :axis_labels => [x_label],
    )
    puts "options: #{options.inspect}"

    # inject data AFTER we dumped options to stdout
    options.update(:data => [sent, archived, starred, trashed])

    chart = Gchart.line(options.dup)
    puts "URL: #{chart}" if ('url' == options[:format])
  end
end

