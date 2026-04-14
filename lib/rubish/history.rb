# frozen_string_literal: true

module Rubish
  # History handling for the shell REPL
  # Supports HISTFILE, HISTSIZE, HISTCONTROL, HISTIGNORE, and history expansion
  module History
    # Get the history file path from HISTFILE or default
    def history_file
      ENV['HISTFILE'] || File.expand_path('~/.rubish_history')
    end

    # Get HISTSIZE (max entries in memory), default 500
    def histsize
      size = ENV['HISTSIZE']
      return 500 if size.nil? || size.empty?
      size.to_i
    end

    # Get HISTFILESIZE (max lines in file), default 500
    def histfilesize
      size = ENV['HISTFILESIZE']
      return 500 if size.nil? || size.empty?
      size.to_i
    end

    # Load history from HISTFILE
    def load_history
      file = history_file
      return unless File.exist?(file)

      max_entries = histsize
      # If HISTSIZE is 0 or negative, don't load history
      return if max_entries <= 0

      begin
        lines = File.readlines(file, chomp: true)
        # Filter out empty lines
        lines = lines.reject(&:empty?)
        # Only keep the last HISTSIZE entries
        lines = lines.last(max_entries) if lines.size > max_entries
        lines.each { |line| Reline::HISTORY << line }
        # Track where we are for history -a (append)
        Builtins.last_history_line = Reline::HISTORY.size
      rescue SystemCallError, IOError => e
        $stderr.puts "rubish: cannot read history file: #{e.message}"
      end
    end

    # Save history to HISTFILE
    def save_history
      file = history_file
      max_lines = histfilesize

      # If HISTFILESIZE is 0 or negative, don't save history
      return if max_lines <= 0

      begin
        # Create directory if needed
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        if Builtins.shopt_enabled?('histappend')
          # histappend: append new entries to history file
          history = Reline::HISTORY.to_a
          last_line = Builtins.last_history_line
          new_entries = history[last_line..]

          if new_entries && !new_entries.empty?
            File.open(file, 'a') do |f|
              new_entries.each { |line| f.puts(line) }
            end
          end

          # Truncate file if it exceeds HISTFILESIZE
          truncate_history_file(file, max_lines)
        else
          # Default: overwrite history file
          history = Reline::HISTORY.to_a

          # hist_save_no_dups: remove duplicates before saving (keep last occurrence)
          if Builtins.zsh_option_enabled?('hist_save_no_dups')
            seen = Set.new
            history = history.reverse.reject { |line| !seen.add?(line) }.reverse
          end

          # Only keep the last HISTFILESIZE entries
          if history.size > max_lines
            # hist_expire_dups_first: when trimming, remove duplicates before oldest unique entries
            if Builtins.zsh_option_enabled?('hist_expire_dups_first')
              history = expire_dups_first(history, max_lines)
            else
              history = history.last(max_lines)
            end
          end

          File.open(file, 'w') do |f|
            history.each { |line| f.puts(line) }
          end
        end
      rescue SystemCallError, IOError => e
        $stderr.puts "rubish: cannot write history file: #{e.message}"
      end
    end

    # Trim history to max_lines, removing duplicates first before oldest unique entries
    def expire_dups_first(history, max_lines)
      excess = history.size - max_lines
      return history if excess <= 0

      # Find duplicate entries (entries that appear more than once), preferring to remove earlier ones
      indices_to_remove = []
      seen = {}
      history.each_with_index do |line, i|
        if seen.key?(line)
          indices_to_remove << seen[line]  # mark earlier occurrence for removal
          seen[line] = i
        else
          seen[line] = i
        end
      end

      # Remove enough duplicates, oldest first
      indices_to_remove.sort!
      indices_to_remove = indices_to_remove.first(excess)

      if indices_to_remove.size >= excess
        # We can trim enough by removing duplicates alone
        result = []
        remove_set = indices_to_remove.to_set
        history.each_with_index { |line, i| result << line unless remove_set.include?(i) }
        result
      else
        # Remove all duplicates we found, then trim from the front
        result = []
        remove_set = indices_to_remove.to_set
        history.each_with_index { |line, i| result << line unless remove_set.include?(i) }
        result.last(max_lines)
      end
    end

    # Truncate history file to max_lines if needed
    def truncate_history_file(file, max_lines)
      return unless File.exist?(file)

      lines = File.readlines(file, chomp: true)

      # hist_save_no_dups: deduplicate before writing (keep last occurrence)
      if Builtins.zsh_option_enabled?('hist_save_no_dups')
        seen = Set.new
        lines = lines.reverse.reject { |line| !seen.add?(line) }.reverse
      end

      return if lines.size <= max_lines

      # Keep only the last max_lines
      File.open(file, 'w') do |f|
        lines.last(max_lines).each { |line| f.puts(line) }
      end
    end

    # Append new history entries to HISTFILE (for history -a)
    def append_history
      file = history_file
      max_lines = histfilesize
      return if max_lines <= 0

      begin
        history = Reline::HISTORY.to_a
        last_line = Builtins.last_history_line
        new_entries = history[last_line..]
        return if new_entries.nil? || new_entries.empty?

        # Create directory if needed
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.open(file, 'a') do |f|
          new_entries.each { |line| f.puts(line) }
        end

        Builtins.last_history_line = history.size
      rescue SystemCallError, IOError => e
        $stderr.puts "rubish: cannot append to history file: #{e.message}"
      end
    end

    # Update history to combine multi-line command into single entry
    def update_multiline_history(lines)
      return if lines.size <= 1
      return if Reline::HISTORY.empty?

      # Remove the first line that was already added to history
      last_idx = Reline::HISTORY.size - 1
      Reline::HISTORY.delete_at(last_idx)

      # Add the combined command
      combined = if Builtins.shopt_enabled?('lithist')
                   lines.join("\n")
                 else
                   lines.join('; ')
                 end
      Reline::HISTORY << combined
    end

    # Update the last history entry to include heredoc content
    # This is called after heredoc content is collected
    # cmdhist: save multi-line commands as single history entry (default on)
    # lithist: preserve newlines in multi-line history (default off)
    def update_history_with_heredoc(command_line, delimiter, heredoc_content)
      return unless Builtins.shopt_enabled?('cmdhist')
      return if Reline::HISTORY.empty?

      # Build the full command with heredoc
      full_command = if Builtins.shopt_enabled?('lithist')
                       # Preserve newlines: command\nheredoc_content\ndelimiter
                       "#{command_line}\n#{heredoc_content}#{delimiter}"
                     else
                       # Replace newlines with semicolons for the heredoc content
                       # But format it as a single line: cat <<EOF; content; EOF
                       content_lines = heredoc_content.chomp.split("\n")
                       "#{command_line} #{content_lines.join('; ')}; #{delimiter}"
                     end

      # Replace the last history entry with the full command
      last_idx = Reline::HISTORY.size - 1
      Reline::HISTORY.delete_at(last_idx)
      Reline::HISTORY << full_command
    end

    # Add command to history based on HISTCONTROL and HISTIGNORE settings
    # HISTCONTROL values (colon-separated):
    #   ignorespace  - don't save commands starting with space
    #   ignoredups   - don't save if same as previous command
    #   ignoreboth   - ignorespace + ignoredups
    #   erasedups    - erase all previous duplicates before adding
    # HISTIGNORE: colon-separated patterns to ignore
    def add_to_history(line, started_with_space: false)
      return if line.empty?

      histcontrol = ENV['HISTCONTROL'] || ''
      controls = histcontrol.split(':').map(&:strip)

      # Check ignorespace / ignoreboth / hist_ignore_space
      # The caller may pass started_with_space when the line has already been stripped
      if (started_with_space || line.start_with?(' ')) && (controls.include?('ignorespace') || controls.include?('ignoreboth') || Builtins.zsh_option_enabled?('hist_ignore_space'))
        return
      end

      # Check hist_no_store: don't record the history command itself
      if Builtins.zsh_option_enabled?('hist_no_store')
        return if line.strip == 'history' || line.strip.match?(/\Ahistory\s/)
      end

      # Check hist_reduce_blanks: normalize whitespace before storing
      if Builtins.zsh_option_enabled?('hist_reduce_blanks')
        line = line.strip.gsub(/\s+/, ' ')
      end

      # Check ignoredups / ignoreboth / hist_ignore_dups
      if controls.include?('ignoredups') || controls.include?('ignoreboth') || Builtins.zsh_option_enabled?('hist_ignore_dups')
        last_entry = Reline::HISTORY.to_a.last
        return if last_entry == line
      end

      # Check HISTIGNORE patterns
      if should_ignore_for_history?(line)
        return
      end

      # Handle erasedups / hist_ignore_all_dups - remove all previous occurrences
      if controls.include?('erasedups') || Builtins.zsh_option_enabled?('hist_ignore_all_dups')
        # Find and remove all duplicates
        indices_to_remove = []
        Reline::HISTORY.each_with_index do |entry, i|
          indices_to_remove << i if entry == line
        end
        # Remove in reverse order to maintain correct indices
        indices_to_remove.reverse_each do |i|
          Reline::HISTORY.delete_at(i)
          Builtins.remove_history_timestamp(i)
        end
      end

      # Add to history with timestamp
      index = Reline::HISTORY.size
      Reline::HISTORY << line
      Builtins.record_history_timestamp(index)

      # Send to syslog if syslog_history is enabled
      log_to_syslog(line) if Builtins.shopt_enabled?('syslog_history')
    end

    # Log command to syslog (for syslog_history shopt)
    def log_to_syslog(command)
      Syslog.open('rubish', Syslog::LOG_PID, Syslog::LOG_USER) do |s|
        s.info('HISTORY: PID=%d UID=%d %s', Process.pid, Process.uid, command)
      end
    rescue SystemCallError
      # Syslog may not be available on all platforms
    end

    # Check if command matches any HISTIGNORE pattern
    # HISTIGNORE is colon-separated list of patterns
    # Patterns support glob-style matching (* and ?)
    # Exact patterns match the entire command line
    def should_ignore_for_history?(line)
      histignore = ENV['HISTIGNORE']
      return false if histignore.nil? || histignore.empty?

      patterns = histignore.split(':')

      patterns.any? do |pattern|
        pattern = pattern.strip
        next false if pattern.empty?

        # Convert pattern to regex for matching
        # All patterns are treated as glob patterns (even without * or ?)
        regex = glob_to_regex(pattern)
        line.match?(regex)
      end
    end

    # Convert simple glob pattern to regex for HISTIGNORE
    def glob_to_regex(pattern)
      regex_str = +'^'
      pattern.each_char do |c|
        case c
        when '*'
          regex_str << '.*'
        when '?'
          regex_str << '.'
        when '.', '^', '$', '+', '|', '(', ')', '[', ']', '{', '}', '\\'
          regex_str << '\\' << c
        else
          regex_str << c
        end
      end
      regex_str << '$'
      Regexp.new(regex_str)
    end

    # Check for history expansion without side effects (for histverify)
    def expand_history_only(line)
      # Capture any output to suppress it during verification check
      original_stdout = $stdout
      $stdout = StringIO.new
      begin
        expand_history(line)
      ensure
        $stdout = original_stdout
      end
    end

    def expand_history(line)
      # History expansion with word designators and modifiers
      # Format: !event[:word][:modifier...]
      # Returns [expanded_line, was_expanded, failed]
      # If histexpand (set -H) is disabled, don't expand history
      return [line, false, false] unless Builtins.set_option?('H')
      # Don't expand history in sourced files (bash behavior)
      return [line, false, false] if Builtins.sourcing_file
      return [line, false, false] unless line.include?('!') || line.start_with?('^')

      history = Reline::HISTORY.to_a
      return [line, false, false] if history.empty?

      result = +''
      i = 0
      expanded = false
      print_only = false
      in_single_quotes = false
      in_double_quotes = false

      while i < line.length
        char = line[i]

        # Track quote state - no expansion in single quotes
        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          result << char
          i += 1
          next
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          result << char
          i += 1
          next
        end

        # Quick substitution: ^old^new^
        if i == 0 && char == '^' && !in_single_quotes
          if line =~ /\A\^([^^]*)\^([^^]*)\^?/
            old_str = $1
            new_str = $2
            last_cmd = history[-1]
            if last_cmd&.include?(old_str)
              return [last_cmd.sub(old_str, new_str), true, false]
            else
              puts 'rubish: substitution failed'
              return [nil, false, true]
            end
          end
        end

        if char == '!' && !in_single_quotes
          expansion, consumed, error, is_print_only = parse_history_expansion(line, i, history)
          if error
            puts error
            return [nil, false, true]
          end
          if expansion
            result << expansion
            expanded = true
            print_only ||= is_print_only
            i += consumed
          else
            result << '!'
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      # If :p modifier was used, print but don't execute
      if print_only
        puts result
        return [nil, false, false]
      end

      [result, expanded, false]
    end

    def parse_history_expansion(line, pos, history)
      # Parse history expansion starting at pos
      # Returns [expansion, chars_consumed, error_message, print_only]
      i = pos + 1  # skip !
      return [nil, 0, nil, false] if i >= line.length

      # Parse event designator
      event_cmd, event_len, error = parse_event_designator(line, i, history)
      return [nil, 0, error, false] if error
      return [nil, 0, nil, false] unless event_cmd

      i += event_len
      args = parse_command_args(event_cmd)

      # Check for word designator
      selected_words = args  # default: all words
      if i < line.length && line[i] == ':'
        # Could be word designator or modifier
        word_result, word_len = parse_word_designator(line, i + 1, args)
        if word_result
          selected_words = word_result
          i += 1 + word_len
        end
      end

      # Check for modifiers
      result_text = selected_words.join(' ')
      print_only = false

      while i < line.length && line[i] == ':'
        modifier, mod_len, mod_error = parse_modifier(line, i + 1, result_text)
        break unless modifier || mod_error
        if mod_error
          return [nil, 0, mod_error, false]
        end
        if modifier == :print_only
          print_only = true
          i += 1 + mod_len
        else
          result_text = modifier
          i += 1 + mod_len
        end
      end

      [result_text, i - pos, nil, print_only]
    end

    def parse_event_designator(line, pos, history)
      # Returns [command, chars_consumed, error]
      return [nil, 0, nil] if pos >= line.length

      char = line[pos]

      case char
      when '!'
        # !! - last command
        [history[-1], 1, nil]
      when '$'
        # !$ - last argument (shorthand, no word designator needed)
        args = parse_command_args(history[-1] || '')
        [args.last || '', 1, nil]
      when '^'
        # !^ - first argument
        args = parse_command_args(history[-1] || '')
        [args[1] || '', 1, nil]
      when '*'
        # !* - all arguments
        args = parse_command_args(history[-1] || '')
        [args[1..].join(' '), 1, nil]
      when '-'
        # !-n - nth previous command
        if line[pos + 1..] =~ /\A(\d+)/
          n = $1.to_i
          cmd = history[-n]
          if cmd
            [cmd, 1 + $1.length, nil]
          else
            [nil, 0, "rubish: !-#{n}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when /\d/
        # !n - command number n
        if line[pos..] =~ /\A(\d+)/
          n = $1.to_i
          cmd = history[n - 1]
          if cmd
            [cmd, $1.length, nil]
          else
            [nil, 0, "rubish: !#{n}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when '?'
        # !?string - contains string
        if line[pos + 1..] =~ /\A([^?\s:]+)\??/
          search = $1
          cmd = history.reverse.find { |c| c.include?(search) }
          if cmd
            consumed = 1 + search.length
            consumed += 1 if line[pos + consumed] == '?'
            [cmd, consumed, nil]
          else
            [nil, 0, "rubish: !?#{search}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when /[a-zA-Z]/
        # !string - starts with string
        if line[pos..] =~ /\A([a-zA-Z][^\s:]*)/
          search = $1
          cmd = history.reverse.find { |c| c.start_with?(search) }
          if cmd
            [cmd, search.length, nil]
          else
            [nil, 0, "rubish: !#{search}: event not found"]
          end
        else
          [nil, 0, nil]
        end
      when ' ', "\t", nil
        [nil, 0, nil]
      else
        [nil, 0, nil]
      end
    end

    def parse_word_designator(line, pos, args)
      # Returns [selected_words_array, chars_consumed] or [nil, 0]
      return [nil, 0] if pos >= line.length

      case line[pos]
      when '0'
        # :0 - command name
        [[args[0] || ''], 1]
      when '^'
        # :^ - first argument
        [[args[1] || ''], 1]
      when '$'
        # :$ - last argument
        [[args.last || ''], 1]
      when '*'
        # :* - all arguments
        [args[1..] || [], 1]
      when '-'
        # :-n - from 0 to n
        if line[pos + 1..] =~ /\A(\d+)/
          end_n = $1.to_i
          [args[0..end_n] || [], 1 + $1.length]
        else
          [nil, 0]
        end
      when /\d/
        # :n or :n-m or :n-$ or :n* or :n-
        if line[pos..] =~ /\A(\d+)(-(\d+|\$|\*)?|\*)?/
          start_n = $1.to_i
          range_part = $2
          consumed = $1.length + (range_part&.length || 0)

          if range_part.nil?
            # Just :n
            [[args[start_n] || ''], consumed]
          elsif range_part == '*'
            # :n* - from n to end
            [args[start_n..] || [], consumed]
          elsif range_part == '-'
            # :n- - from n to last-1
            [args[start_n...-1] || [], consumed]
          elsif range_part.start_with?('-')
            end_part = range_part[1..]
            if end_part == '$' || end_part == '*'
              # :n-$ or :n-*
              [args[start_n..] || [], consumed]
            elsif end_part.empty?
              # :n- - from n to last-1
              [args[start_n...-1] || [], consumed]
            else
              # :n-m
              end_n = end_part.to_i
              [args[start_n..end_n] || [], consumed]
            end
          else
            [[args[start_n] || ''], $1.length]
          end
        else
          [nil, 0]
        end
      else
        [nil, 0]
      end
    end

    def parse_modifier(line, pos, text)
      # Returns [modified_text_or_symbol, chars_consumed, error]
      return [nil, 0, nil] if pos >= line.length

      case line[pos]
      when 'h'
        # :h - head (dirname)
        [File.dirname(text), 1, nil]
      when 't'
        # :t - tail (basename)
        [File.basename(text), 1, nil]
      when 'r'
        # :r - remove extension
        ext = File.extname(text)
        [ext.empty? ? text : text[0...-ext.length], 1, nil]
      when 'e'
        # :e - extension only
        ext = File.extname(text)
        [ext.empty? ? '' : ext[1..], 1, nil]
      when 'p'
        # :p - print only, don't execute
        [:print_only, 1, nil]
      when 'q'
        # :q - quote the text
        [Shellwords.escape(text), 1, nil]
      when 's', 'g'
        # :s/old/new/ or :gs/old/new/ - substitute
        global = line[pos] == 'g'
        start = global ? pos + 1 : pos
        return [nil, 0, nil] unless start < line.length && line[start] == 's'
        return [nil, 0, nil] unless start + 1 < line.length

        delimiter = line[start + 1]
        return [nil, 0, nil] unless delimiter && delimiter =~ /[\/^]/

        # Find old_str (between first and second delimiter)
        old_start = start + 2
        old_end = line.index(delimiter, old_start)
        return [nil, 0, 'rubish: bad substitution'] unless old_end

        old_str = line[old_start...old_end]

        # Find new_str (between second and optional third delimiter)
        new_start = old_end + 1
        new_end = line.index(delimiter, new_start) || line.length
        # Check if new_end is followed by word boundary or modifier
        if new_end < line.length && line[new_end] == delimiter
          new_str = line[new_start...new_end]
          consumed = new_end - pos + 1  # include trailing delimiter
        else
          # No trailing delimiter, find end of word
          new_end = new_start
          while new_end < line.length && line[new_end] !~ /[\s:]/
            new_end += 1
          end
          new_str = line[new_start...new_end]
          consumed = new_end - pos
        end

        if global
          [text.gsub(old_str, new_str), consumed, nil]
        else
          [text.sub(old_str, new_str), consumed, nil]
        end
      when '&'
        # :& - repeat last substitution (not implemented, skip)
        [nil, 0, nil]
      else
        [nil, 0, nil]
      end
    end

    def parse_command_args(cmd)
      # Simple tokenization for history expansion
      # Handles quoted strings
      args = []
      current = +''
      in_single = false
      in_double = false
      i = 0

      while i < cmd.length
        char = cmd[i]
        if char == "'" && !in_double
          in_single = !in_single
          current << char
        elsif char == '"' && !in_single
          in_double = !in_double
          current << char
        elsif char =~ /\s/ && !in_single && !in_double
          args << current unless current.empty?
          current = +''
        else
          current << char
        end
        i += 1
      end
      args << current unless current.empty?
      args
    end
  end
end
