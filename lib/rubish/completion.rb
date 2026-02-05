# frozen_string_literal: true

module Rubish
  # Tab completion handling for the shell REPL
  # Supports programmable completion (bash-style), file completion, command completion,
  # and fish-style abbreviated path expansion
  module Completion
    # Quote shell metacharacters in completion results
    # These characters need escaping to prevent shell interpretation
    SHELL_METACHARACTERS = " \t\n|&;()<>!{}$`\\\"'*?[]#~=%".chars.to_set.freeze

    # Set up key bindings for navigating the autocompletion dialog
    # These bindings are context-sensitive: they navigate the dialog when open,
    # otherwise fall back to default behavior (history nav, cursor movement)
    def setup_completion_dialog_keybindings
      # Add context-sensitive navigation methods to LineEditor first
      # (this must be done before any readline calls)
      setup_completion_context_sensitive_navigation

      config = Reline.core.config

      # Use bind_key to add to @additional_key_bindings which has higher priority
      # than @default_key_bindings. This ensures our bindings won't be overridden
      # by Reline's lazy initialization of terminfo-based key bindings.

      # Arrow keys for dialog navigation (single item)
      # Up arrow: ESC [ A, Down arrow: ESC [ B
      config.bind_key('"\e[A"', 'completion_or_up')
      config.bind_key('"\e[B"', 'completion_or_down')

      # Also support alternate arrow key sequences (some terminals use ESC O instead of ESC [)
      config.bind_key('"\eOA"', 'completion_or_up')
      config.bind_key('"\eOB"', 'completion_or_down')

      # Ctrl-N/Ctrl-P for dialog navigation (falls back to history when no dialog)
      config.bind_key('"\C-n"', 'completion_or_next_history')
      config.bind_key('"\C-p"', 'completion_or_prev_history')

      # Ctrl-F/Ctrl-B for page-style navigation (falls back to cursor movement when no dialog)
      config.bind_key('"\C-f"', 'completion_page_or_forward_char')
      config.bind_key('"\C-b"', 'completion_page_or_backward_char')
    end

    # Add context-sensitive navigation methods to Reline::LineEditor
    # These check if a completion dialog is open and dispatch accordingly
    def setup_completion_context_sensitive_navigation
      # Number of items to jump per page
      page_size = 5

      Reline::LineEditor.prepend(Module.new do
        # Helper to check if completion dialog is active and visible
        # Note: @completion_journey_state alone is not enough - Reline sets it
        # whenever the buffer is modified with autocompletion enabled, even if
        # no dialog is shown. We must check if the autocomplete dialog has contents.
        define_method(:completion_dialog_active?) do
          return false unless @config.autocompletion && @completion_journey_state
          # Check if autocomplete dialog is actually visible (has contents)
          @dialogs&.any? { |dialog| dialog.name == :autocomplete && dialog.contents }
        end

        # Helper to navigate history without triggering autocompletion
        # Sets @completion_occurs to prevent Reline from starting a new
        # completion journey after the history item is loaded
        define_method(:navigate_history) do |direction, key|
          if direction == :prev
            ed_prev_history(key)
          else
            ed_next_history(key)
          end
          # Prevent autocompletion from triggering after history navigation
          # This is checked in input_key at lines 1057-1060
          @completion_occurs = true
        end

        # Arrow up: navigate dialog or do nothing (arrows don't have default action in line editor)
        define_method(:completion_or_up) do |key|
          if completion_dialog_active?
            completion_journey_move(:up)
          else
            navigate_history(:prev, key)
          end
        end

        # Arrow down: navigate dialog or do nothing
        define_method(:completion_or_down) do |key|
          if completion_dialog_active?
            completion_journey_move(:down)
          else
            navigate_history(:next, key)
          end
        end

        # Ctrl-N: navigate dialog down or next history
        define_method(:completion_or_next_history) do |key|
          if completion_dialog_active?
            completion_journey_move(:down)
          else
            navigate_history(:next, key)
          end
        end

        # Ctrl-P: navigate dialog up or prev history
        define_method(:completion_or_prev_history) do |key|
          if completion_dialog_active?
            completion_journey_move(:up)
          else
            navigate_history(:prev, key)
          end
        end

        # Ctrl-F: page down in dialog or forward char
        define_method(:completion_page_or_forward_char) do |key|
          if completion_dialog_active?
            page_size.times { completion_journey_move(:down) }
          else
            ed_next_char(key)
          end
        end

        # Ctrl-B: page up in dialog or backward char
        define_method(:completion_page_or_backward_char) do |key|
          if completion_dialog_active?
            page_size.times { completion_journey_move(:up) }
          else
            ed_prev_char(key)
          end
        end
      end)
    end

    # Set up abbreviated path expansion (like zsh)
    # When Tab is pressed on an abbreviated path, expand it directly in the line
    def setup_abbreviated_path_expansion
      repl = self

      # Define a custom method on LineEditor to handle abbreviated path expansion
      Reline::LineEditor.prepend(Module.new do
        define_method(:complete) do |*args|
          # Get current line and cursor position
          line = whole_buffer
          point = @byte_pointer

          # Find the current word
          line_to_cursor = line.byteslice(0, point) || ''
          word_start = line_to_cursor.rindex(/[ \t]/)
          word_start = word_start ? word_start + 1 : 0
          word = line_to_cursor.byteslice(word_start..-1) || ''

          # Check if it's an abbreviated path that needs expansion
          if word.include?('/') && !word.start_with?('/') && !Dir.glob("#{word}*").any?
            expanded_paths = repl.send(:expand_abbreviated_path_for_completion_full, word)
            if expanded_paths && expanded_paths.length == 1
              # Single match - expand inline
              expanded = expanded_paths.first
              # Replace the word in the buffer
              new_line = line.byteslice(0, word_start).to_s + expanded + (line.byteslice(point..-1) || '')
              @buffer_of_lines = [new_line]
              @byte_pointer = word_start + expanded.bytesize
              @cursor = word_start + expanded.length
              @cursor_max = new_line.length
              return
            elsif expanded_paths && expanded_paths.length > 1
              # Multiple matches - find common prefix and expand to that
              common = expanded_paths.first
              expanded_paths[1..].each do |path|
                common = common.chars.zip(path.chars).take_while { |a, b| a == b }.map(&:first).join
              end
              if common.length > word.length
                new_line = line.byteslice(0, word_start).to_s + common + (line.byteslice(point..-1) || '')
                @buffer_of_lines = [new_line]
                @byte_pointer = word_start + common.bytesize
                @cursor = word_start + common.length
                @cursor_max = new_line.length
                return
              end
            end
          end

          # Fall back to normal completion
          super(*args)
        end
      end)
    end

    # Expand abbreviated path returning full paths: l/r/re -> ["lib/rubish/repl.rb"]
    def expand_abbreviated_path_for_completion_full(input)
      Builtins.expand_abbreviated_path_for_completion(input, full_paths: true)
    end

    def complete(input)
      line = Reline.line_buffer
      point = Reline.point rescue line.length

      # no_empty_cmd_completion: do not complete on empty command line
      if Builtins.shopt_enabled?('no_empty_cmd_completion') && line.strip.empty?
        return []
      end

      # Environment variable completion: $PA -> $PATH
      # Also handle ${PA -> ${PATH} (Reline splits on { so we only get PA)
      if input.start_with?('$')
        return complete_variable(input)
      end

      # Check if we're inside ${...} by looking at context before current word
      # Reline splits on { so input might be just "PA" when user typed "${PA"
      # We need to return "PATH}" (not "${PATH}") so Reline replaces "PA" correctly
      line_to_point = line[0, point] || ''
      if line_to_point =~ /\$\{([A-Za-z_][A-Za-z0-9_]*)?\z/
        # We're completing inside ${...}, return VAR} format
        prefix = input
        results = []
        ENV.keys.each do |key|
          results << "#{key}}" if key.start_with?(prefix)
        end
        Builtins.shell_var_names.each do |key|
          candidate = "#{key}}"
          results << candidate if key.start_with?(prefix) && !results.include?(candidate)
        end
        return results.uniq.sort
      end

      # hostcomplete: attempt hostname completion when input starts with @
      if Builtins.shopt_enabled?('hostcomplete') && input.start_with?('@')
        hostname_prefix = input[1..]  # Remove the @ prefix
        hostnames = complete_hostname(hostname_prefix)
        return hostnames.map { |h| "@#{h}" } unless hostnames.empty?
      end

      # Parse command line into words up to cursor position
      line_to_cursor = line[0, point]
      words = split_completion_words(line_to_cursor)
      # Check if we're completing the first word (command) or an argument
      # If cursor is after a word break character, we're starting a new (empty) word
      wordbreaks = Builtins.comp_wordbreaks
      cursor_after_wordbreak = point > 0 && wordbreaks.include?(line[point - 1])
      is_first_word = words.empty? || (words.length == 1 && !cursor_after_wordbreak)

      if is_first_word
        complete_command(input)
      else
        # Check for programmable completion (only if progcomp is enabled)
        cmd = words.first
        spec = Builtins.shopt_enabled?('progcomp') ? Builtins.get_completion_spec(cmd) : nil

        if spec && spec[:function]
          # Calculate COMP_CWORD (index of word containing cursor)
          cword = calculate_comp_cword(line, point, words)

          # Set up COMP_* variables
          Builtins.set_completion_context(
            line: line,
            point: point,
            words: words,
            cword: cword,
            type: 9,  # TAB = normal completion
            key: 9    # TAB key
          )

          begin
            # Call the completion function
            # First check for builtin completion functions, then user-defined
            prev = words[cword - 1] || ''
            if Builtins.builtin_completion_function?(spec[:function])
              Builtins.call_builtin_completion_function(spec[:function], cmd, input, prev)
            else
              call_function(spec[:function], [cmd, input, prev])
            end

            # Get results from COMPREPLY array (synced from shell array for user-defined functions)
            # Shell functions modify the COMPREPLY array via set_array, so read from there
            results = Builtins.get_array('COMPREPLY').dup
            # Also check the class variable for builtin completion functions
            results = Builtins.compreply.dup if results.empty? && !Builtins.compreply.empty?

            # Apply filter pattern if specified
            if spec[:filterpat] && !results.empty?
              pattern = Regexp.new(spec[:filterpat].gsub('*', '.*').gsub('?', '.'))
              results.reject! { |r| r.match?(pattern) }
            end

            # Filter results by current input (like readline does)
            results.select! { |r| r.start_with?(input) } unless input.empty?

            # Filter out options when completing subcommands
            # (e.g., rbenv commands returns --version but we don't want to suggest it for "rbenv <tab>")
            unless input.start_with?('-')
              results.reject! { |r| r.start_with?('-') }
            end

            # Add prefix/suffix if specified
            if spec[:prefix] || spec[:suffix]
              results.map! { |r| "#{spec[:prefix]}#{r}#{spec[:suffix]}" }
            end

            return results.uniq.sort
          ensure
            Builtins.clear_completion_context
          end
        elsif spec
          # Use spec without function (wordlist, actions, etc.)
          return Builtins.generate_completions(spec, input)
        else
          # Try auto-completion by parsing --help output (fish-style)
          cword = calculate_comp_cword(line, point, words)
          Builtins.set_completion_context(
            line: line,
            point: point,
            words: words,
            cword: cword,
            type: 9,
            key: 9
          )

          begin
            prev = words[cword - 1] || ''
            Builtins.call_builtin_completion_function('_auto', cmd, input, prev)
            results = Builtins.compreply.dup

            if results && !results.empty?
              results.select! { |r| r.start_with?(input) } unless input.empty?
              return results.uniq.sort
            end
          ensure
            Builtins.clear_completion_context
          end

          # Fall back to file completion
          complete_file(input)
        end
      end
    end

    def split_completion_words(line)
      # Split line into words using COMP_WORDBREAKS
      # Handles: backslash escapes, quotes, $'...', $(cmd), <(cmd), >(cmd), ${var}, {a,b,c}
      wordbreaks = Builtins.comp_wordbreaks
      words = []
      current = +''
      pos = 0

      while pos < line.length
        c = line[pos]
        two_char = line[pos, 2]

        # Backslash escape - skip next character
        if c == '\\'
          current << c
          pos += 1
          if pos < line.length
            current << line[pos]
            pos += 1
          end
          next
        end

        # ANSI-C quoting: $'...'
        if two_char == "$'"
          start = pos
          pos += 2  # skip $'
          while pos < line.length
            if line[pos] == '\\'
              pos += 2  # skip escaped char
            elsif line[pos] == "'"
              pos += 1
              break
            else
              pos += 1
            end
          end
          current << line[start...pos]
          next
        end

        # Command substitution: $(...)
        if two_char == '$('
          start = pos
          pos += 2  # skip $(
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '('
              depth += 1
            elsif line[pos] == ')'
              depth -= 1
            elsif line[pos] == '"' || line[pos] == "'"
              # Skip quoted content
              quote = line[pos]
              pos += 1
              while pos < line.length && line[pos] != quote
                pos += 2 if line[pos] == '\\'
                pos += 1
              end
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Variable expansion: ${...}
        if two_char == '${'
          start = pos
          pos += 2  # skip ${
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '{'
              depth += 1
            elsif line[pos] == '}'
              depth -= 1
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Process substitution: <(...) or >(...)
        if two_char == '<(' || two_char == '>('
          start = pos
          pos += 2  # skip <( or >(
          depth = 1
          while pos < line.length && depth > 0
            if line[pos] == '('
              depth += 1
            elsif line[pos] == ')'
              depth -= 1
            elsif line[pos] == '"' || line[pos] == "'"
              quote = line[pos]
              pos += 1
              while pos < line.length && line[pos] != quote
                pos += 2 if line[pos] == '\\'
                pos += 1
              end
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Brace expansion: {...}
        # Only if it looks like brace expansion (contains comma or ..)
        if c == '{' && looks_like_brace_expansion_at?(line, pos)
          start = pos
          depth = 1
          pos += 1
          while pos < line.length && depth > 0
            if line[pos] == '{'
              depth += 1
            elsif line[pos] == '}'
              depth -= 1
            end
            pos += 1
          end
          current << line[start...pos]
          next
        end

        # Double-quoted string
        if c == '"'
          current << c
          pos += 1
          while pos < line.length && line[pos] != '"'
            if line[pos] == '\\'
              current << line[pos]
              pos += 1
              if pos < line.length
                current << line[pos]
                pos += 1
              end
            else
              current << line[pos]
              pos += 1
            end
          end
          if pos < line.length
            current << line[pos]  # closing quote
            pos += 1
          end
          next
        end

        # Single-quoted string
        if c == "'"
          current << c
          pos += 1
          while pos < line.length && line[pos] != "'"
            current << line[pos]
            pos += 1
          end
          if pos < line.length
            current << line[pos]  # closing quote
            pos += 1
          end
          next
        end

        # Backtick command substitution: `...`
        if c == '`'
          start = pos
          pos += 1
          while pos < line.length
            if line[pos] == '\\'
              pos += 2
            elsif line[pos] == '`'
              pos += 1
              break
            else
              pos += 1
            end
          end
          current << line[start...pos]
          next
        end

        # Word break character
        if wordbreaks.include?(c)
          words << current unless current.empty?
          current = +''
          pos += 1
          next
        end

        # Regular character
        current << c
        pos += 1
      end

      words << current unless current.empty?
      words
    end

    def looks_like_brace_expansion_at?(line, pos)
      # Check if { at pos looks like brace expansion {a,b} or {1..5}
      # Not: variable ${var} or function body { cmd; }
      return false unless line[pos] == '{'

      depth = 1
      i = pos + 1
      has_comma = false
      has_dotdot = false

      while i < line.length && depth > 0
        case line[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
        when ','
          has_comma = true if depth == 1
        when '.'
          if line[i + 1] == '.'
            has_dotdot = true if depth == 1
            i += 1
          end
        when ' ', "\t", "\n"
          # Whitespace inside braces suggests function body, not brace expansion
          return false if depth > 0
        end
        i += 1
      end

      depth == 0 && (has_comma || has_dotdot)
    end

    def calculate_comp_cword(line, point, words)
      # Find which word the cursor is in
      pos = 0
      words.each_with_index do |word, idx|
        word_start = line.index(word, pos)
        break idx if word_start.nil?
        word_end = word_start + word.length
        return idx if point >= word_start && point <= word_end
        pos = word_end
      end
      words.length
    end

    # Complete hostnames from /etc/hosts and HOSTFILE
    def complete_hostname(prefix)
      hostnames = Set.new

      # Read from /etc/hosts
      if File.exist?('/etc/hosts')
        begin
          File.readlines('/etc/hosts').each do |line|
            # Skip comments and empty lines
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            # Parse: IP hostname [aliases...]
            parts = line.split(/\s+/)
            next if parts.length < 2

            # Skip the IP address, collect hostnames
            parts[1..].each do |hostname|
              hostnames << hostname if hostname.start_with?(prefix)
            end
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Can't read file, skip
        end
      end

      # Also read from HOSTFILE if set
      hostfile = ENV['HOSTFILE']
      if hostfile && File.exist?(hostfile)
        begin
          File.readlines(hostfile).each do |line|
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            parts = line.split(/\s+/)
            next if parts.length < 2

            parts[1..].each do |hostname|
              hostnames << hostname if hostname.start_with?(prefix)
            end
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Can't read file, skip
        end
      end

      hostnames.to_a.sort
    end

    # Complete environment and shell variable names
    def complete_variable(input)
      # Handle ${VAR} form - complete inside braces
      if input.start_with?('${')
        prefix = input[2..]  # Remove ${
        closing = '}'
        dollar_prefix = '${'
      else
        # Handle $VAR form
        prefix = input[1..]  # Remove $
        closing = ''
        dollar_prefix = '$'
      end

      results = []

      # Environment variables
      ENV.keys.each do |key|
        results << "#{dollar_prefix}#{key}#{closing}" if key.start_with?(prefix)
      end

      # Shell variables (from Builtins.shell_vars)
      Builtins.shell_var_names.each do |key|
        candidate = "#{dollar_prefix}#{key}#{closing}"
        results << candidate if key.start_with?(prefix) && !results.include?(candidate)
      end

      results.uniq.sort
    end

    def complete_command(input)
      # If input contains /, complete as file path (e.g., ./script, ../bin/cmd, /usr/bin/ruby)
      # Only show directories and executable files since we're completing a command
      if input.include?('/')
        return complete_file(input).select do |f|
          f.end_with?('/') || File.executable?(f.chomp(' '))
        end
      end

      results = []

      # Builtins
      Builtins::COMMANDS.each do |cmd|
        results << cmd if cmd.start_with?(input)
      end

      # User-defined functions
      @functions.keys.each do |name|
        results << name if name.start_with?(input)
      end

      # Commands from PATH
      ENV['PATH'].split(':').each do |dir|
        next unless Dir.exist?(dir)

        Dir.foreach(dir) do |file|
          next if file.start_with?('.')
          next unless file.start_with?(input)

          path = File.join(dir, file)
          results << file if File.executable?(path)
        end
      rescue Errno::EACCES
        # Skip directories we can't read
      end

      results.uniq.sort
    end

    def complete_file(input)
      # Always expand ~ for globbing (Dir.glob doesn't expand tilde)
      glob_input = input.sub(/^~(?=\/|$)/, Dir.home)
      # direxpand: also expand $VAR when enabled
      if Builtins.shopt_enabled?('direxpand')
        glob_input = expand_for_completion(glob_input)
      end

      candidates = Dir.glob("#{glob_input}*").map do |f|
        File.directory?(f) ? "#{f}/" : f
      end.sort

      # Partial path expansion: l/r/re -> l/r/repl.rb (abbreviated form for Reline)
      # Try to expand each path segment if no direct matches
      if candidates.empty? && glob_input.include?('/')
        abbrev_candidates = expand_abbreviated_path_for_completion(glob_input)
        candidates = abbrev_candidates if abbrev_candidates && !abbrev_candidates.empty?
      end

      # dirspell: if no matches and dirspell is enabled, try to correct directory spelling
      if candidates.empty? && Builtins.shopt_enabled?('dirspell')
        corrected = correct_completion_path(input)
        if corrected && corrected != input
          candidates = Dir.glob("#{corrected}*").map do |f|
            File.directory?(f) ? "#{f}/" : f
          end.sort
        end
      end

      # Apply FIGNORE filtering
      # force_fignore: when enabled (default), FIGNORE is always applied
      # when disabled, if only one completion remains, don't filter it out
      fignore = ENV['FIGNORE']
      if fignore && !fignore.empty?
        suffixes = fignore.split(':').reject(&:empty?)
        unless suffixes.empty?
          filtered = candidates.reject do |f|
            # Don't filter directories
            next false if f.end_with?('/')
            suffixes.any? { |suffix| f.end_with?(suffix) }
          end

          if Builtins.shopt_enabled?('force_fignore')
            # Always apply FIGNORE, even if it filters out the only match
            candidates = filtered unless filtered.empty?
          else
            # Without force_fignore, don't filter if only one candidate would remain
            # and it would be filtered out
            if filtered.empty? && candidates.length == 1
              # Keep the single candidate even though it matches FIGNORE
            else
              candidates = filtered unless filtered.empty?
            end
          end
        end
      end

      # complete_fullquote: quote shell metacharacters in completion results
      if Builtins.shopt_enabled?('complete_fullquote')
        candidates = candidates.map { |c| quote_completion_metacharacters(c) }
      end

      # Convert paths back to ~/... form after quoting (so tilde isn't escaped)
      if input.start_with?('~/') && !Builtins.shopt_enabled?('direxpand')
        candidates = candidates.map { |c| c.sub(/^#{Regexp.escape(Dir.home)}/, '~') }
      end

      candidates
    end

    # Expand abbreviated path for completion: l/r/re -> ["l/r/repl.rb"]
    def expand_abbreviated_path_for_completion(input)
      Builtins.expand_abbreviated_path_for_completion(input)
    end

    # Expand abbreviated directory path: l/r -> lib/rubish
    def expand_abbreviated_dir(dir_path)
      Builtins.expand_abbreviated_dir(dir_path)
    end

    # Quote shell metacharacters in completion results
    def quote_completion_metacharacters(str)
      result = +''
      str.each_char do |c|
        if SHELL_METACHARACTERS.include?(c)
          result << '\\' << c
        else
          result << c
        end
      end
      result
    end

    # Expand tilde and variables for completion (direxpand)
    def expand_for_completion(input)
      result = input

      # Expand ~ at the beginning
      if result.start_with?('~')
        if result == '~' || result.start_with?('~/')
          # ~/... -> /home/user/...
          result = result.sub(/^~/, Dir.home)
        elsif result =~ /^~([^\/]+)(.*)/
          # ~username/... -> /home/username/...
          username = $1
          rest = $2
          begin
            user_home = Dir.home(username)
            result = "#{user_home}#{rest}"
          rescue ArgumentError
            # Unknown user, leave as is
          end
        end
      end

      # Expand shell variables $VAR or ${VAR}
      result = result.gsub(/\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)/) do
        var_name = $1 || $2
        Builtins.get_var(var_name) || $&
      end

      result
    end

    # Correct directory spelling errors in a completion path
    def correct_completion_path(input)
      # Split into directory part and filename part
      if input.include?('/')
        dir_part = File.dirname(input)
        file_part = File.basename(input)
      else
        # No directory part, nothing to correct
        return nil
      end

      # Try to correct the directory part
      corrected_dir = Builtins.correct_directory_spelling(dir_part)
      return nil unless corrected_dir

      # Return corrected path with original file part
      File.join(corrected_dir, file_part)
    end
  end
end
