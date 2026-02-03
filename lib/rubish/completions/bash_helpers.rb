# frozen_string_literal: true

module Rubish
  module Builtins
    # =========================================================================
    # Bash-completion helper functions
    # These implement the standard bash-completion helper functions for
    # compatibility with bash-completion scripts.
    # =========================================================================

    # _get_comp_words_by_ref - Get completion words with special word-break handling
    # Options:
    #   -n EXCLUDE  - Characters to exclude from COMP_WORDBREAKS
    #   -c VAR      - Store current word in VAR (default: cur)
    #   -p VAR      - Store previous word in VAR (default: prev)
    #   -w VAR      - Store words array in VAR (default: words)
    #   -i VAR      - Store cword index in VAR (default: cword)
    def _get_comp_words_by_ref(args)
      exclude_chars = ''
      cur_var = 'cur'
      prev_var = 'prev'
      words_var = 'words'
      cword_var = 'cword'

      i = 0
      while i < args.length
        case args[i]
        when '-n'
          i += 1
          exclude_chars = args[i] || ''
        when '-c'
          i += 1
          cur_var = args[i] if args[i]
        when '-p'
          i += 1
          prev_var = args[i] if args[i]
        when '-w'
          i += 1
          words_var = args[i] if args[i]
        when '-i'
          i += 1
          cword_var = args[i] if args[i]
        when 'cur'
          # Legacy positional argument
        when 'prev'
          # Legacy positional argument
        when 'words'
          # Legacy positional argument
        when 'cword'
          # Legacy positional argument
        end
        i += 1
      end

      # Get base completion context
      words = @comp_words.dup
      cword = @comp_cword
      line = @comp_line
      point = @comp_point

      # If excluding characters from wordbreaks, re-split the line
      unless exclude_chars.empty?
        wordbreaks = comp_wordbreaks.chars.reject { |c| exclude_chars.include?(c) }.join
        words, cword = resplit_comp_words(line, point, wordbreaks)
      end

      cur = words[cword] || ''
      prev = cword > 0 ? (words[cword - 1] || '') : ''

      # Set variables via the local scope or environment
      ENV[cur_var] = cur
      ENV[prev_var] = prev
      set_array(words_var, words)
      ENV[cword_var] = cword.to_s

      true
    end

    # Helper to re-split completion words with different wordbreaks
    def resplit_comp_words(line, point, wordbreaks)
      words = []
      current = +''
      in_quote = nil
      pos = 0

      line.each_char.with_index do |c, idx|
        if in_quote
          current << c
          in_quote = nil if c == in_quote
        elsif c == '"' || c == "'"
          current << c
          in_quote = c
        elsif c == '\\'
          current << c
          # Skip next char
        elsif wordbreaks.include?(c)
          words << current unless current.empty?
          current = +''
        else
          current << c
        end
      end
      words << current unless current.empty?

      # Calculate cword based on point
      cword = 0
      char_pos = 0
      words.each_with_index do |word, idx|
        word_start = line.index(word, char_pos)
        break unless word_start
        word_end = word_start + word.length
        if point >= word_start && point <= word_end
          cword = idx
          break
        end
        char_pos = word_end
        cword = idx + 1
      end

      [words, [cword, words.length - 1].min]
    end

    # _init_completion - Initialize completion with common setup
    # Options:
    #   -n EXCLUDE  - Characters to exclude from COMP_WORDBREAKS
    #   -s          - Split on = for --option=value
    def _init_completion(args)
      exclude_chars = ''
      split_on_equals = false

      i = 0
      while i < args.length
        case args[i]
        when '-n'
          i += 1
          exclude_chars = args[i] || ''
        when '-s'
          split_on_equals = true
        end
        i += 1
      end

      # Call _get_comp_words_by_ref with the exclude chars
      ref_args = []
      ref_args += ['-n', exclude_chars] unless exclude_chars.empty?
      _get_comp_words_by_ref(ref_args)

      # Handle --option=value splitting if requested
      if split_on_equals
        cur = ENV['cur'] || ''
        if cur.include?('=')
          # Split on first =
          parts = cur.split('=', 2)
          ENV['cur'] = parts[1] || ''
          ENV['prev'] = parts[0]
        end
      end

      # Set COMPREPLY to empty
      @compreply = []

      true
    end

    # Get list of system users for ~username completion
    # Only returns users with home directories in typical user locations
    def get_system_users
      users = []
      # Try /etc/passwd (works on most Unix-like systems)
      if File.exist?('/etc/passwd')
        File.readlines('/etc/passwd').each do |line|
          next if line.start_with?('#') || line.strip.empty?
          user = line.split(':').first
          users << user if user && !user.empty?
        end
      end
      # On macOS, also check Open Directory for regular users
      if RUBY_PLATFORM.include?('darwin')
        output = `dscl . -list /Users 2>/dev/null`
        output.lines.each { |line| users << line.strip }
      end
      # Filter to users with home directories in /Users or /home
      users.uniq.select do |user|
        home = File.expand_path("~#{user}") rescue nil
        home && File.directory?(home) && (home.start_with?('/Users/') || home.start_with?('/home/'))
      end.sort
    end

    # _filedir - Complete filenames, optionally filtering by extension/type
    # Arguments: [extension_pattern]
    # Options:
    #   -d  - Only directories
    def _filedir(args)
      dirs_only = false
      pattern = nil

      args.each do |arg|
        if arg == '-d'
          dirs_only = true
        elsif !arg.start_with?('-')
          pattern = arg
        end
      end

      cur = ENV['cur'] || ''

      # Username completion: ~prefix without /
      if cur.start_with?('~') && !cur.include?('/')
        prefix = cur[1..]  # Remove leading ~
        users = get_system_users.select { |u| u.start_with?(prefix) }
        results = users.map { |u| "~#{u}/" }
        # Add ~/ at the top if prefix is empty
        results.unshift('~/') if prefix.empty?
        set_array('COMPREPLY', results)
        return true
      end

      # Expand tilde (may fail if ~username refers to non-existent user)
      expanded_cur = cur.start_with?('~') ? (File.expand_path(cur) rescue cur) : cur

      # Get directory and prefix
      if cur.end_with?('/')
        # Path ends with / - list contents of that directory
        dir = expanded_cur
        prefix = ''
      elsif cur.include?('/')
        dir = File.dirname(expanded_cur)
        prefix = File.basename(expanded_cur)
      else
        dir = '.'
        prefix = expanded_cur
      end

      results = []

      begin
        Dir.entries(dir).each do |entry|
          next if entry == '.' || entry == '..'
          # Skip hidden files unless user explicitly typed a dot prefix
          next if entry.start_with?('.') && !prefix.start_with?('.')
          next unless entry.start_with?(prefix) || prefix.empty?

          full_path = File.join(dir, entry)

          if dirs_only
            next unless File.directory?(full_path)
          end

          if pattern && !File.directory?(full_path)
            # Check if file matches the pattern
            next unless File.fnmatch(pattern, entry, File::FNM_EXTGLOB)
          end

          # Build the completion string
          if cur.end_with?('/')
            result = "#{cur}#{entry}"
          elsif cur.include?('/')
            result = File.join(File.dirname(cur), entry)
          else
            result = entry
          end

          # Add trailing slash for directories
          result += '/' if File.directory?(full_path)

          results << result
        end
      rescue Errno::ENOENT, Errno::EACCES
        # Directory doesn't exist or can't be accessed
      end

      # Add to COMPREPLY
      current = get_array('COMPREPLY')
      set_array('COMPREPLY', current + results.sort)
      true
    end

    # _have - Check if a command exists in PATH
    def _have(args)
      return false if args.empty?

      cmd = args[0]

      # Check builtins
      return true if builtin?(cmd)

      # Check PATH
      path_dirs = (ENV['PATH'] || '').split(':')
      path_dirs.any? do |dir|
        path = File.join(dir, cmd)
        File.executable?(path) && !File.directory?(path)
      end
    end

    # _split_longopt - Handle --option=value completion
    # Sets prev to option, cur to value after =
    def _split_longopt(args)
      cur = ENV['cur'] || ''

      return false unless cur.include?('=')

      parts = cur.split('=', 2)
      ENV['prev'] = parts[0]
      ENV['cur'] = parts[1] || ''

      # Store for later restoration
      ENV['__SPLIT_LONGOPT_PREV'] = parts[0]
      ENV['__SPLIT_LONGOPT'] = 'set'

      true
    end

    # __ltrim_colon_completions - Remove colon prefix from completions
    # Handles the case where cur contains colons (e.g., package:version)
    def _ltrim_colon_completions(args)
      cur = args[0] || ENV['cur'] || ''

      return true unless cur.include?(':')

      # Find where the colon is and trim completions to match
      colon_pos = cur.rindex(':')
      return true unless colon_pos

      prefix = cur[0..colon_pos]

      # Trim prefix from all completions
      trimmed = get_array('COMPREPLY').map do |comp|
        if comp.start_with?(prefix)
          comp[prefix.length..]
        else
          comp
        end
      end
      set_array('COMPREPLY', trimmed)

      true
    end

    # _variables - Complete variable names
    def _variables(args)
      cur = ENV['cur'] || ''

      # Remove leading $ if present
      prefix = cur.start_with?('$') ? cur[1..] : cur

      results = []

      # Environment variables
      ENV.keys.each do |key|
        results << "$#{key}" if key.start_with?(prefix)
      end

      # Shell arrays
      @state.arrays.keys.each do |key|
        results << "$#{key}" if key.start_with?(prefix)
      end

      current = get_array('COMPREPLY')
      set_array('COMPREPLY', current + results.sort)
      true
    end

    # _tilde - Complete tilde expressions (~username)
    def _tilde(args)
      cur = ENV['cur'] || ''

      return true unless cur.start_with?('~')

      prefix = cur[1..] || ''
      results = []

      # Get usernames from /etc/passwd or similar
      begin
        if File.exist?('/etc/passwd')
          File.readlines('/etc/passwd').each do |line|
            username = line.split(':').first
            next unless username
            results << "~#{username}/" if username.start_with?(prefix)
          end
        end
      rescue Errno::EACCES
        # Can't read passwd file
      end

      # Also try using getent if available
      begin
        `getent passwd 2>/dev/null`.each_line do |line|
          username = line.split(':').first
          next unless username
          results << "~#{username}/" if username.start_with?(prefix)
        end
      rescue
        # getent not available
      end

      current = get_array('COMPREPLY')
      set_array('COMPREPLY', current + results.sort.uniq)
      true
    end

    # _quote_readline_by_ref - Quote a string for readline
    # Sets the named variable to the quoted string
    def _quote_readline_by_ref(args)
      return false if args.length < 2

      varname = args[0]
      value = args[1]

      # Quote special characters for readline
      quoted = value.gsub(/([\\'"$`\s])/, '\\\\\1')

      ENV[varname] = quoted
      true
    end

    # _parse_help - Parse --help output to extract options
    # Usage: _parse_help command [option]
    def _parse_help(args)
      return false if args.empty?

      cmd = args[0]
      help_opt = args[1] || '--help'

      results = []

      begin
        # Run command with help option and capture output
        output = `#{cmd} #{help_opt} 2>&1`

        # Parse options from the output
        output.each_line do |line|
          # Match patterns like:
          #   -o, --option
          #   --option
          #   -o
          line.scan(/(?:^|\s)(-{1,2}[a-zA-Z0-9][-a-zA-Z0-9_]*)/) do |match|
            opt = match[0]
            results << opt unless results.include?(opt)
          end
        end
      rescue
        # Command failed
      end

      # Filter by current word if set
      cur = ENV['cur'] || ''
      unless cur.empty?
        results = results.select { |opt| opt.start_with?(cur) }
      end

      @compreply = (@compreply || []) + results.sort
      true
    end

    # _upvars - Set variables in caller's scope (simplified implementation)
    # Usage: _upvars [-v varname value]... [-a arrayname values...]...
    def _upvars(args)
      i = 0
      while i < args.length
        case args[i]
        when '-v'
          # Set scalar variable
          varname = args[i + 1]
          value = args[i + 2]
          if varname && value
            ENV[varname] = value
          end
          i += 3
        when '-a'
          # Set array variable: -a N arrayname values...
          count = (args[i + 1] || '0').to_i
          arrayname = args[i + 2]
          if arrayname && count > 0
            values = args[(i + 3)...(i + 3 + count)]
            set_array(arrayname, values)
          end
          i += 3 + count
        else
          i += 1
        end
      end
      true
    end

    # _usergroup - Complete usernames or user:group combinations
    # Options:
    #   -u  - Complete usernames only
    #   -g  - Complete groups only
    def _usergroup(args)
      users_only = args.include?('-u')
      groups_only = args.include?('-g')

      cur = ENV['cur'] || ''
      results = []

      # Check if we're completing group part (after :)
      if cur.include?(':') && !users_only
        prefix = cur.split(':').last || ''
        user_part = cur.split(':').first

        # Complete groups
        begin
          if File.exist?('/etc/group')
            File.readlines('/etc/group').each do |line|
              group = line.split(':').first
              next unless group
              results << "#{user_part}:#{group}" if group.start_with?(prefix)
            end
          end
        rescue Errno::EACCES
        end
      elsif !groups_only
        # Complete users
        begin
          if File.exist?('/etc/passwd')
            File.readlines('/etc/passwd').each do |line|
              username = line.split(':').first
              next unless username
              results << username if username.start_with?(cur)
            end
          end
        rescue Errno::EACCES
        end
      end

      @compreply = (@compreply || []) + results.sort.uniq
      true
    end
  end
end
