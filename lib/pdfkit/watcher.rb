class PDFKit
  class PDFGenerationError < StandardError
    def initialize(msg)
      super("Generation failed: #{msg}")
    end
  end

  class Watcher
    def initialize(file, opts)
      @file = file
      @delay = opts[:with_delay] || 0
      @timeout = opts[:timeout] || 300
    end

    def watch_for_end_of_file(&block)
      start = Time.now
      sleep @delay unless @delay.zero?

      found = false
      timeout = false
      f = nil

      while !found && !timeout do
        if File.exists?(@file)
          unless f
            f = File.open(@file, 'r')
          end

          f.seek(-4, IO::SEEK_END) # "EOF\n" == 4 bytes
          line = f.gets

          if read_as_utf8(line) =~ /EOF\n/
            block.call
            found = true
          end
        end

        if !found
          if Time.now > start + @timeout
            block.call
            timeout = true
            raise PDFGenerationError.new("generation timed out")
          end
        end
        sleep(100)
      end
      f.close if f
    end

    def read_as_utf8(str)
      return '' if str.nil?
      str.unpack('C*').pack('U*')
    end
  end
end
