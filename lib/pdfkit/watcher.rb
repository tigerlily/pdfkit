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

    def watch_for(pattern, &block)
      start = Time.now
      sleep @delay unless @delay.zero?

      f = File.open(@file, "r")
      f.seek(0,IO::SEEK_END)
      while true do
        select([f])
        line = f.gets
        if read_as_utf8(line) =~ pattern
          block.call(read_as_utf8(line), pattern)
          break
        else
          if Time.now > start + @timeout
            block.call(read_as_utf8(line), pattern)
            raise PDFGenerationError.new("generation timed out")
            break
          end
        end
      end
      f.close
    end

    def read_as_utf8(str)
      return '' if str.nil?
      str.unpack('C*').pack('U*')
    end
  end
end
