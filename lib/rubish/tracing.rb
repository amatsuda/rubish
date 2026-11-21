# frozen_string_literal: true

module Rubish
  # What the shell says about each simple command as it runs: the `set -x`
  # trace and the BASH_COMMAND text. Shared by the REPL and the execution
  # context, which both dispatch commands.
  module Tracing
    # The words of a command the way bash's trace prints them: quoted only
    # when they need it
    def self.words_text(words)
      leading = true
      words.map do |word|
        word = word.to_s
        if leading && word =~ /\A([a-zA-Z_][a-zA-Z0-9_]*(?:\[[^\]]*\])?\+?=)(.*)\z/m
          # a leading assignment quotes only its value: x='a b'
          "#{$1}#{trace_word($2)}"
        else
          leading = false
          trace_word(word)
        end
      end.join(' ')
    end

    def self.trace_word(word)
      return "''" if word.empty?
      return word if word.match?(%r{\A[\w%+,./:=@^-]+\z})

      "'" + word.gsub("'", "'\\\\''") + "'"
    end

    # One text per simple command in a runnable result
    def self.texts_for(result)
      case result
      when Command then [words_text([result.name, *result.args])]
      when Pipeline then result.commands.select { |c| c.is_a?(Command) }.map { |c| words_text([c.name, *c.args]) }
      else []
      end
    end

    # Record a command that is about to run and trace it under set -x
    def announce_command(result)
      announce_texts(Tracing.texts_for(result))
    end

    def announce_words(name, args)
      announce_texts([Tracing.words_text([name, *args])])
    end

    def announce_texts(texts)
      return if texts.empty?

      # While a trap runs, BASH_COMMAND stays the command that triggered it
      @state.bash_command = texts.join(' | ') if @state.current_trapsig.to_s.empty?
      texts.each { |text| xtrace(text) } if Builtins.set_option?('x')
    end

    def xtrace(line)
      # Print trace with PS4 prefix (default: '+ ')
      # PS4 supports the same escape sequences as PS1
      ps4 = ENV['PS4'] || '+ '
      expanded_ps4 = expand_prompt(ps4)
      output = "#{expanded_ps4}#{line}"

      # Check RUBISH_XTRACEFD (or BASH_XTRACEFD for compatibility)
      xtracefd = ENV['RUBISH_XTRACEFD'] || ENV['BASH_XTRACEFD']
      if xtracefd && !xtracefd.empty?
        fd_num = xtracefd.to_i
        if fd_num >= 0 && xtracefd =~ /\A\d+\z/
          begin
            # Use IO.for_fd with autoclose: false to avoid closing the fd when done
            io = IO.for_fd(fd_num, 'w', autoclose: false)
            io.puts output
            io.flush
          rescue Errno::EBADF
            # Invalid file descriptor, fall back to stderr
            $stderr.puts "rubish: #{fd_num}: Bad file descriptor"
            $stderr.puts output
          rescue SystemCallError, IOError
            $stderr.puts output
          end
        else
          # Not a valid number, use stderr
          $stderr.puts output
        end
      else
        $stderr.puts output
      end
    end
  end
end
