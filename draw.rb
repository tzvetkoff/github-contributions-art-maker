#!/usr/bin/env ruby

require 'date'
require 'optparse'
require 'shellwords'

class GitHubContributionsArtMaker
  attr_reader :args, :input, :output, :pre, :post, :source, :names, :emails, :messages

  class << self
    def run!(args)
      new(args).run!
    end
  end

  def initialize(args)
    @args     = args
    @input    = $stdin
    @output   = $stdout
    @names    = Deque.new
    @emails   = Deque.new
    @messages = Deque.new
  end

  def run!
    parse_args!
    load_defaults!
    read_input!
    validate_input!
    write_output!
  end

  private

  def wrap(s)
    s.lstrip.lines.map.with_index do |line, idx|
      idx > 0 ? ' ' * 37 + line.strip : line.strip
    end.join("\n") + "\n\n"
  end

  def parse_args!
    parser = OptionParser.new do |o|
      o.banner = 'Usage:'
      o.separator "    #{$0} [options]"
      o.separator ''
      o.separator 'Options:'

      h = <<~EOT
        Set input file.
        Default: $stdin.
      EOT
      o.on('-i INPUT', '--input=INPUT', wrap(h)) do |v|
        @input = File.open(v, 'r')
      end

      h = <<~EOT
        Set output file.
        Default: $stdout.
      EOT
      o.on('-o OUTPUT', '--output=OUTPUT', wrap(h)) do |v|
        @output = File.open(v, 'w')
      end

      h = <<~EOT
        Set GIT_AUTHOR_NAME & GIT_COMMITTER_NAME.
        Allows multiple values.
        If prefixed with @, it will threat the argument as a file.
        Default: `No One`.
      EOT
      o.on('-n NAME', '--name=NAME', wrap(h)) do |v|
        if v.start_with?('@')
          names.values = File.read(v[1..-1]).lines.map(&:strip)
        else
          names.values << v
        end
      end

      h = <<~EOT
        Set email for GIT_AUTHOR_EMAIL & GIT_COMMITTER_EMAIL.
        Allows multiple values.
        If prefixed with @, it will threat the argument as a file.
        Default: `example@example.org`.
      EOT
      o.on('-e EMAIL', '--email=EMAIL', wrap(h)) do |v|
        if v.start_with?('@')
          emails.values = File.read(v[1..-1]).lines.map(&:strip)
        else
          emails.values << v
        end
      end

      h = <<~EOT
        Set commit message.
        Allows multiple values.
        If prefixed with @, it will threat the argument as a file.
        Default: `@commit_messages.txt`.
      EOT
      o.on('-m MESSAGE', '--message=MESSAGE', wrap(h)) do |v|
        if v.start_with?('@')
          messages.values = File.read(v[1..-1]).lines.map(&:strip)
        else
          messages.values << v
        end
      end

      h = <<~EOT
        Append a file before git commands.
        Default: empty.
      EOT
      o.on('--pre=FILE', wrap(h)) do |v|
        @pre = v
      end

      h = <<~EOT
        Append a file after git commands.
        Default: empty.
      EOT
      o.on('--post=FILE', wrap(h)) do |v|
        @post = v
      end

      o.on_tail('-h', '--help', 'Print this message and exit.') do
        puts o
        exit
      end
    end

    @args = parser.parse!(args)
    if args.length > 0
      $stderr.puts "#{$0}: wrong number of arguments (given #{args.length}, expected 0)"
    end
  rescue OptionParser::InvalidOption => e
    $stderr.puts "#{$0}: #{e}"
    $stderr.puts
    $stderr.puts parser
    exit
  end

  def load_defaults!
    names.values << 'No One' if @names.values.empty?
    emails.values << 'example@example.org' if @emails.values.empty?
    messages.values = File.read(File.expand_path 'commit_messages.txt', __dir__).lines.map(&:strip) if @messages.values.empty?
  end

  def read_input!
    @source = input.read.lines.map{ |line| line.strip.gsub('|', '').chars }
  end

  def validate_input!
    raise 'source should not contain more than 7 lines' if source.length > 7
    raise 'source lines differ in length' if source.map(&:length).uniq.length != 1
    raise 'source contains lines longer than 52 chars' if source.map.any?{ |line| line.length > 54 }
  rescue RuntimeError => e
    $stderr.puts "#{$0}: #{e}"
    exit
  end

  def write_output!
    output.puts '#!/usr/bin/env bash'
    output.puts

    output.write(File.read(pre)) if pre

    output.puts 'git add .'
    output.puts

    today = Date.today
    end_of_last_week = today - today.wday
    beginning_of_graph_year = end_of_last_week - 52 * 7

    source.each_with_index do |line, line_idx|
      line.each_with_index do |char, char_idx|
        count = char.to_i(36)

        if count > 0
          count.times do |minute|
            name = @names.next
            email = @emails.next
            message = @messages.next
            date = beginning_of_graph_year + char_idx * 7 + line_idx
            minute = '%02d' % minute
            s = []
            s << "GIT_AUTHOR_DATE=#{date.to_s}\\ 10:#{minute}:00"
            s << "GIT_COMMITTER_DATE=#{date.to_s}\\ 10:#{minute}:00"
            s << "GIT_AUTHOR_NAME=#{Shellwords.escape(name)}"
            s << "GIT_COMMITTER_NAME=#{Shellwords.escape(name)}"
            s << "GIT_AUTHOR_EMAIL=#{Shellwords.escape(email)}"
            s << "GIT_COMMITTER_EMAIL=#{Shellwords.escape(email)}"
            s << "git commit --allow-empty --allow-empty-message -m #{Shellwords.escape(message)}"
            @output.puts(s.join(' '))
          end
          @output.puts
        end
      end
    end

    output.write(File.read(post)) if post
  end

  class Deque
    attr_accessor :values, :index

    def initialize(values = [], index = 0)
      @values, @index = values, index
    end

    def next
      if @index >= @values.length
        @index = 0
      end

      result = @values[@index]
      @index += 1
      result
    end
  end
end

if $0 == __FILE__
  GitHubContributionsArtMaker.run!(ARGV)
end
