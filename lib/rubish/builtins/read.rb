# frozen_string_literal: true

module Rubish
  module Builtins
    def read(args)
      # Options
      opts = {
        prompt: nil,
        array_name: nil,
        delimiter: "\n",
        use_readline: false,
        initial_text: nil,
        nchars: nil,
        nchars_exact: nil,
        raw: false,
        silent: false,
        timeout: nil,
        fd: nil
      }
      vars = []

      # Parse options
      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-a'
          opts[:array_name] = args[i + 1]
          i += 2
        when '-d'
          delim = args[i + 1]
          opts[:delimiter] = delim&.slice(0, 1) || "\n"
          i += 2
        when '-e'
          opts[:use_readline] = true
          i += 1
        when '-i'
          opts[:initial_text] = args[i + 1]
          i += 2
        when '-n'
          opts[:nchars] = args[i + 1]&.to_i
          i += 2
        when '-N'
          opts[:nchars_exact] = args[i + 1]&.to_i
          i += 2
        when '-p'
          opts[:prompt] = args[i + 1]
          i += 2
        when '-r'
          opts[:raw] = true
          i += 1
        when '-s'
          opts[:silent] = true
          i += 1
        when '-t'
          opts[:timeout] = args[i + 1]&.to_f
          i += 2
        when '-u'
          opts[:fd] = args[i + 1]&.to_i
          i += 2
        else
          vars << arg
          i += 1
        end
      end

      # Default variable is REPLY (unless using array mode)
      vars << 'REPLY' if vars.empty? && opts[:array_name].nil?

      # Read input
      line = read_input_line(opts)
      return false if line.nil?

      # Process backslash escapes unless raw mode
      unless opts[:raw]
        line = process_read_escapes(line)
      end

      # Store in array or variables
      if opts[:array_name]
        store_read_array(opts[:array_name], line)
      elsif opts[:nchars_exact]
        # -N mode: store raw content without splitting
        vars.each { |var| ENV[var] = line }
      else
        store_read_variables(vars, line)
      end

      true
    end

    def read_input_line(opts)
      input_stream = opts[:fd] ? IO.new(opts[:fd]) : $stdin

      # Use readline if -e specified
      if opts[:use_readline] && $stdin.tty?
        return read_with_readline(opts)
      end

      # Display prompt
      if opts[:prompt]
        $stderr.print opts[:prompt]
        $stderr.flush
      end

      # Handle silent mode
      if opts[:silent] && $stdin.tty?
        return read_silent(input_stream, opts)
      end

      # Handle timeout (-t option or TMOUT environment variable)
      timeout = opts[:timeout] || tmout
      if timeout && timeout > 0
        opts[:timeout] = timeout
        return read_with_timeout(input_stream, opts)
      end

      # Handle character count modes
      if opts[:nchars_exact]
        return read_exact_chars(input_stream, opts[:nchars_exact])
      elsif opts[:nchars]
        return read_nchars(input_stream, opts[:nchars], opts[:delimiter])
      end

      # Normal line reading with custom delimiter
      read_until_delimiter(input_stream, opts[:delimiter])
    end

    def read_with_readline(opts)
      prompt = opts[:prompt] || ''

      if opts[:initial_text]
        # Pre-fill the input buffer
        Reline.pre_input_hook = -> {
          Reline.insert_text(opts[:initial_text])
          Reline.pre_input_hook = nil
        }
      end

      begin
        line = Reline.readline(prompt, false)
        return nil unless line
        line
      rescue Interrupt
        puts
        return nil
      end
    end

    def read_silent(input_stream, opts)
      line = +''
      delimiter = opts[:delimiter]
      nchars = opts[:nchars] || opts[:nchars_exact]

      begin
        input_stream.noecho do |io|
          if nchars
            nchars.times do
              char = io.getc
              break unless char
              break if char == delimiter && !opts[:nchars_exact]
              line << char
            end
          else
            loop do
              char = io.getc
              break unless char
              break if char == delimiter
              line << char
            end
          end
        end
        puts if $stdin.tty?  # Print newline after silent input
        line
      rescue Errno::ENOTTY
        # Not a terminal, fall back to normal read
        if nchars
          input_stream.read(nchars)&.chomp(delimiter)
        else
          read_until_delimiter(input_stream, delimiter)
        end
      end
    end

    def read_with_timeout(input_stream, opts)
      begin
        Timeout.timeout(opts[:timeout]) do
          if opts[:nchars_exact]
            read_exact_chars(input_stream, opts[:nchars_exact])
          elsif opts[:nchars]
            read_nchars(input_stream, opts[:nchars], opts[:delimiter])
          else
            read_until_delimiter(input_stream, opts[:delimiter])
          end
        end
      rescue Timeout::Error
        nil
      end
    end

    def read_exact_chars(input_stream, count)
      # -N: read exactly count chars, ignoring delimiters
      input_stream.read(count)
    end

    def read_nchars(input_stream, count, delimiter)
      # -n: read up to count chars or until delimiter
      line = +''
      count.times do
        char = input_stream.getc
        break unless char
        break if char == delimiter
        line << char
      end
      line
    end

    def read_until_delimiter(input_stream, delimiter)
      if delimiter == "\n"
        line = input_stream.gets
        return nil unless line
        line.chomp
      else
        line = +''
        loop do
          char = input_stream.getc
          break unless char
          break if char == delimiter
          line << char
        end
        line.empty? && input_stream.eof? ? nil : line
      end
    end

    def process_read_escapes(line)
      # Process backslash escapes (line continuation)
      # In read without -r, backslash at end of line continues to next line
      # and backslash before any char removes special meaning
      result = +''
      i = 0
      while i < line.length
        if line[i] == '\\'
          if i + 1 < line.length
            # Backslash escapes next character
            result << line[i + 1]
            i += 2
          else
            # Trailing backslash - in real bash this would continue reading
            # For simplicity, we just skip it
            i += 1
          end
        else
          result << line[i]
          i += 1
        end
      end
      result
    end

    def store_read_array(array_name, line)
      # Split line into words using IFS and store as array
      words = split_by_ifs(line)
      clear_read_array(array_name)

      words.each_with_index do |word, idx|
        ENV["#{array_name}_#{idx}"] = word
      end
      ENV["#{array_name}_LENGTH"] = words.length.to_s
    end

    def clear_read_array(array_name)
      # Clear existing array elements
      length = ENV["#{array_name}_LENGTH"]&.to_i || 0
      length.times do |i|
        ENV.delete("#{array_name}_#{i}")
      end
      ENV.delete("#{array_name}_LENGTH")
    end

    def store_read_variables(vars, line)
      # If only one variable, assign the whole line (with IFS whitespace trimmed)
      if vars.length == 1
        ws_chars = ifs_whitespace
        trimmed = ws_chars.empty? ? line : line.gsub(/\A[#{Regexp.escape(ws_chars)}]+|[#{Regexp.escape(ws_chars)}]+\z/, '')
        ENV[vars[0]] = trimmed
        return
      end

      # Split into at most N parts where N = number of variables
      # This preserves delimiters in the last variable
      words = split_by_ifs_n(line, vars.length)

      vars.each_with_index do |var, idx|
        ENV[var] = words[idx]&.strip || ''
      end
    end
  end
end
