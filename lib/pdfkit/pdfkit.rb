require 'shellwords'
require 'tempfile'

class PDFKit

  class NoExecutableError < StandardError
    def initialize
      msg  = "No wkhtmltopdf executable found at #{PDFKit.configuration.wkhtmltopdf}\n"
      msg << ">> Please install wkhtmltopdf - https://github.com/pdfkit/PDFKit/wiki/Installing-WKHTMLTOPDF"
      super(msg)
    end
  end

  class ImproperSourceError < StandardError
    def initialize(msg)
      super("Improper Source: #{msg}")
    end
  end

  class PDFGenerationError < StandardError
    def initialize(msg)
      super("Generation failed: #{msg}")
    end
  end

  class CommandFailedError < StandardError
    def initialize(msg)
      super("Command failed: #{msg}")
    end
  end

  attr_accessor :source, :stylesheets
  attr_reader :options

  def initialize(url_file_or_html, options = {})
    @source = Source.new(url_file_or_html)

    @stylesheets = []

    @options = PDFKit.configuration.default_options.merge(options)
    @options.merge! find_options_in_meta(url_file_or_html) unless source.url?
    @options = normalize_options(@options)

    raise NoExecutableError.new unless File.exists?(PDFKit.configuration.wkhtmltopdf)
  end

  def command(path = nil, temp_file = nil)
    args = [executable]
    args += @options.to_a.flatten.compact
    args << '--quiet'

    if temp_file
      args << temp_file.path
    elsif @source.html?
      args << '-' # Get HTML from stdin
    else
      args << @source.to_s
    end

    args << (path || '-') # Write to file or stdout

    args.shelljoin
  end

  def executable
    default = PDFKit.configuration.wkhtmltopdf
    return default if default !~ /^\// # its not a path, so nothing we can do
    if File.exist?(default)
      default
    else
      default.split('/').last
    end
  end

  def to_pdf(path=nil, opts)
    append_stylesheets

    tmp    = (opts[:ensure_termination] && @source.html?) ? get_temp_file : nil
    invoke = command(path, tmp)

    result = process_pdf(path, invoke, tmp, opts)

    raise PDFGenerationError.new("#{path}, generation was not completed properly") unless file_complete?(result.to_s)
    # $? is thread safe per http://stackoverflow.com/questions/2164887/thread-safe-external-process-in-ruby-plus-checking-exitstatus
    raise CommandFailedError.new(invoke) if result.to_s.strip.empty? or !$?.success?

    return result
  end

  def file_complete? result
    result[-4,3] == 'EOF'
  end

  def get_temp_file
    tmp = Tempfile.new(['source', '.html'])
    # We encode to UTF-8 to prevent some invalid byte code errors.
    tmp.write(@source.to_s.encode('UTF-8', :undef => :replace, :invalid => :replace, :replace => ""))
    tmp.rewind
    tmp
  end

  # We give the possibility to ensure the termination of the process because
  # wkhtmltopdf 0.10 RC2 never terminates.
  # To do so we need to launch a subprocess, and kill it after a given time (30 by default).
  # Otherwise ( for wkhtmltopdf <= 0.9 ) we can simply go through stdin and invoke the command as it will not hand indefinetly
  #
  # Returns the content of the PDF file.
  def process_pdf(path, invoke, tmp, opts)
    if opts[:ensure_termination]
      timeout = opts[:timeout] || 10
      @process = IO.popen(invoke)

      watcher = PDFKit::Watcher.new(path, with_delay: 10)
      watcher.watch_for(/EOF/) do |line, pattern|
        Process.kill :SIGINT, @process.pid
        tmp.close if tmp
      end

      sleep timeout # Whilst wkhtmltopdf is not fixed, we need to put a sleep on the main thread to make sure the pdf generation has started before continuing
    else
      result = IO.popen(invoke, "wb+") do |pdf|
        pdf.puts(@source.to_s) if @source.html?
        pdf.close_write
        pdf.gets(nil)
      end
    end
    result = File.read(path) if path

    result
  end

  def to_file(path, opts = { ensure_termination: false, timeout: 10 })
    self.to_pdf(path, opts)
    File.new(path)
  end

  protected

    def find_options_in_meta(content)
      # Read file if content is a File
      content = content.read if content.is_a?(File)

      found = {}
      content.scan(/<meta [^>]*>/) do |meta|
        if meta.match(/name=["']#{PDFKit.configuration.meta_tag_prefix}/)
          name = meta.scan(/name=["']#{PDFKit.configuration.meta_tag_prefix}([^"']*)/)[0][0]
          found[name.to_sym] = meta.scan(/content=["']([^"']*)/)[0][0]
        end
      end

      found
    end

    def style_tag_for(stylesheet)
      "<style>#{File.read(stylesheet)}</style>"
    end

    def append_stylesheets
      raise ImproperSourceError.new('Stylesheets may only be added to an HTML source') if stylesheets.any? && !@source.html?

      stylesheets.each do |stylesheet|
        if @source.to_s.match(/<\/head>/)
          @source = Source.new(@source.to_s.gsub(/(<\/head>)/, style_tag_for(stylesheet)+'\1'))
        else
          @source.to_s.insert(0, style_tag_for(stylesheet))
        end
      end
    end

    def normalize_options(options)
      normalized_options = {}

      options.each do |key, value|
        next if !value
        normalized_key = "--#{normalize_arg key}"
        normalized_options[normalized_key] = normalize_value(value)
      end
      normalized_options
    end

    def normalize_arg(arg)
      arg.to_s.downcase.gsub(/[^a-z0-9]/,'-')
    end

    def normalize_value(value)
      case value
      when TrueClass #ie, ==true, see http://www.ruby-doc.org/core-1.9.3/TrueClass.html
        nil
      when Hash
        value.to_a.flatten.collect{|x| x.to_s}
      when Array
        value.flatten.collect{|x| x.to_s}
      else
        value.to_s
      end
    end

end
