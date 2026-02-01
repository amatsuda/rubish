# frozen_string_literal: true

require 'set'
require_relative 'arithmetic'
require_relative 'expansion'
require_relative 'runtime'
require_relative 'runtime/builtins'

module Rubish
  # ExecutionContext is the object in which generated shell code is evaluated.
  # It includes the Builtins module, making all builtin methods available as
  # instance methods. Each REPL session creates its own ExecutionContext with
  # its own ShellState.
  class ExecutionContext
    # POSIX character class mappings for glob patterns
    POSIX_CHAR_CLASSES = {
      'alnum' => 'a-zA-Z0-9',
      'alpha' => 'a-zA-Z',
      'ascii' => '\x00-\x7F',
      'blank' => ' \t',
      'cntrl' => '\x00-\x1F\x7F',
      'digit' => '0-9',
      'graph' => '!-~',
      'lower' => 'a-z',
      'print' => ' -~',
      'punct' => '!-/:-@\\[-`{-~',
      'space' => ' \t\n\r\f\v',
      'upper' => 'A-Z',
      'word' => 'a-zA-Z0-9_',
      'xdigit' => '0-9A-Fa-f'
    }.freeze

    attr_reader :state
    attr_accessor :last_status, :last_bg_pid, :lineno, :pipestatus
    attr_accessor :functions, :heredoc_content, :command_number
    attr_accessor :subshell_level, :rubish_command
    attr_accessor :next_varname_fd, :varname_fds

    def initialize(state)
      @state = state
      @last_status = 0
      @last_bg_pid = nil
      @lineno = 1
      @pipestatus = [0]
      @functions = {}
      @heredoc_content = nil
      @command_number = 1
      @subshell_level = 0
      @rubish_command = ''
      @next_varname_fd = 10
      @varname_fds = {}
      @random_generator = Random.new
      @zsh_completion_initialized = false
      @zsh_completions = {}
      @seconds_base = Time.now
      @help_completion_cache = {}
      @zsh_fpath = nil
      @loaded_builtins = {}
      @coprocs = {}
      @named_directories = {}
      @builtin_completion_functions = {}
      @disabled_builtins = Set.new
      @dynamic_commands = []
      @call_stack = []
      @comp_words = []
      @comp_cword = 0
      @comp_line = ''
      @comp_point = 0
      @comp_type = 0
      @comp_key = 0
      @compreply = []
      @in_err_trap = false
      @in_debug_trap = false
      @in_return_trap = false
      @positional_params = []
      @argv0 = 'rubish'
      @script_name = 'rubish'
      @bash_argv0_unset = false
      @funcname_stack = []
      @rubish_lineno_stack = []
      @rubish_source_stack = []
      @rubish_argc_stack = []
      @rubish_argv_stack = []
      @rubish_command = ''
      @current_source_file = 'main'
    end

    # Delegate to callbacks in state for script name and positional params
    def script_name
      @state.script_name_getter&.call || 'rubish'
    end

    def script_name=(value)
      @state.script_name_setter&.call(value)
    end

    def positional_params
      @positional_params = @state.positional_params_getter&.call || []
    end

    def positional_params=(value)
      @positional_params = value
      @state.positional_params_setter&.call(value)
    end

    # Delegate state attributes for backward compatibility with Builtins.xxx calls
    def sourcing_file
      @state.sourcing_file
    end

    def sourcing_file=(value)
      @state.sourcing_file = value
    end

    def exit_blocked_by_jobs
      @state.exit_blocked_by_jobs
    end

    def exit_blocked_by_jobs=(value)
      @state.exit_blocked_by_jobs = value
    end

    def last_history_line
      @state.last_history_line
    end

    def last_history_line=(value)
      @state.last_history_line = value
    end

    # Methods expected by Runtime module
    def execute(line, skip_history_expansion: false)
      # Delegate to the executor callback in state
      @state.executor&.call(line)
    end

    def run_err_trap_if_failed
      err_trap if @last_status != 0
    end

    def check_errexit
      return if @last_status == 0
      throw(:exit, @last_status) if set_option?('e')
    end

    def bare_assignment?(str)
      return false unless str.is_a?(String)
      str.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*(\[[^\]]*\])?\+?=/)
    end

    def handle_bare_assignments(assignments)
      assignments.each do |assignment|
        if assignment.include?('[')
          # Array element assignment: arr[n]=value or arr[n]+=value
          handle_array_element_assignment(assignment)
        elsif assignment.include?('+=')
          # Append: VAR+=value
          handle_append_assignment(assignment)
        else
          # Regular assignment: VAR=value
          handle_regular_assignment(assignment)
        end
      end
    end

    def call_function_with_redirects(cmd)
      # Set up redirects if present
      saved_stdout = nil
      saved_stdin = nil

      begin
        if cmd.stdout
          saved_stdout = $stdout.dup
          $stdout.reopen(cmd.stdout)
        end
        if cmd.stdin
          saved_stdin = $stdin.dup
          $stdin.reopen(cmd.stdin)
        end

        success = call_function(cmd.name, cmd.args)
        @last_status = success ? 0 : 1
      ensure
        if saved_stdout
          $stdout.reopen(saved_stdout)
          saved_stdout.close
          cmd.stdout.close unless cmd.stdout.closed?
        end
        if saved_stdin
          $stdin.reopen(saved_stdin)
          saved_stdin.close
          cmd.stdin.close unless cmd.stdin.closed?
        end
      end
    end

    def call_function(name, args)
      func_checker = @state.function_checker
      func_caller = @state.function_caller
      if func_checker&.call(name) && func_caller
        func_caller.call(name, args)
      else
        false
      end
    end

    def display_select_menu(items)
      num_width = items.length.to_s.length
      items.each_with_index do |item, i|
        puts "#{(i + 1).to_s.rjust(num_width)}) #{item}"
      end
    end

    private

    def handle_regular_assignment(assignment)
      var, val = assignment.split('=', 2)
      val ||= ''
      # Use handle_scalar_assignment from Expansion module which handles special vars
      handle_scalar_assignment(var, val)
    end

    def handle_append_assignment(assignment)
      var, val = assignment.split('+=', 2)
      val ||= ''
      expanded_val = expand_assignment_value(val)
      current = get_var(var)
      set_var(var, current + expanded_val)
    end

    def handle_array_element_assignment(assignment)
      if assignment =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[([^\]]+)\]\+?=(.*)?\z/
        var = $1
        index_expr = $2
        val = $3 || ''
        is_append = assignment.include?('+=')

        expanded_val = expand_assignment_value(val)
        index = eval_arithmetic_expr(index_expr).to_i

        if is_append
          current = get_array_element(var, index)
          set_array_element(var, index, current + expanded_val)
        else
          set_array_element(var, index, expanded_val)
        end
      end
    end

    def expand_assignment_value(val)
      # Handle ANSI-C quoting: $'...'
      if val.start_with?("$'") && val.end_with?("'")
        return expand_ansi_c_string(val[2...-1])
      end
      # Remove surrounding quotes if present
      if (val.start_with?('"') && val.end_with?('"')) ||
         (val.start_with?("'") && val.end_with?("'"))
        val = val[1...-1]
      end
      # TODO: proper variable expansion
      val
    end

    def expand_ansi_c_string(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\'
          if i + 1 < str.length
            case str[i + 1]
            when 'n' then result << "\n"; i += 2
            when 't' then result << "\t"; i += 2
            when 'r' then result << "\r"; i += 2
            when 'a' then result << "\a"; i += 2
            when 'b' then result << "\b"; i += 2
            when 'e', 'E' then result << "\e"; i += 2
            when 'f' then result << "\f"; i += 2
            when 'v' then result << "\v"; i += 2
            when '\\' then result << "\\"; i += 2
            when "'" then result << "'"; i += 2
            when '"' then result << '"'; i += 2
            when '?' then result << '?'; i += 2
            when /[0-7]/
              # Octal escape: \nnn (1-3 digits)
              octal = str[i + 1..].match(/\A[0-7]{1,3}/)[0]
              result << octal.to_i(8).chr
              i += 1 + octal.length
            when 'x'
              # Hex escape: \xHH (1-2 digits)
              if str[i + 2..] =~ /\A([0-9a-fA-F]{1,2})/
                result << $1.to_i(16).chr
                i += 2 + $1.length
              else
                result << str[i, 2]
                i += 2
              end
            else
              result << str[i, 2]
              i += 2
            end
          else
            result << str[i]
            i += 1
          end
        else
          result << str[i]
          i += 1
        end
      end
      result
    end

    def expand_posix_classes(pattern)
      return pattern unless pattern.include?('[:')
      result = +''
      i = 0
      while i < pattern.length
        if pattern[i] == '['
          bracket_start = i
          j = i + 1
          j += 1 if j < pattern.length && (pattern[j] == '!' || pattern[j] == '^')
          j += 1 if j < pattern.length && pattern[j] == ']'
          while j < pattern.length
            if pattern[j] == '[' && j + 1 < pattern.length && pattern[j + 1] == ':'
              end_pos = pattern.index(':]', j + 2)
              j = end_pos ? end_pos + 2 : j + 1
            elsif pattern[j] == ']'
              break
            else
              j += 1
            end
          end
          if j < pattern.length && pattern[j] == ']'
            bracket_expr = pattern[bracket_start..j]
            expanded = expand_posix_in_bracket(bracket_expr)
            result << expanded
            i = j + 1
          else
            result << pattern[i]
            i += 1
          end
        else
          result << pattern[i]
          i += 1
        end
      end
      result
    end

    def expand_posix_in_bracket(bracket_expr)
      return bracket_expr unless bracket_expr.include?('[:')
      content = bracket_expr[1...-1]
      negation = ''
      if content.start_with?('!') || content.start_with?('^')
        negation = content[0]
        content = content[1..]
      end
      expanded_content = content.gsub(/\[:([a-z]+):\]/) do |match|
        POSIX_CHAR_CLASSES[$1] || match
      end
      "[#{negation}#{expanded_content}]"
    end

    def apply_globignore(matches)
      globignore = ENV['GLOBIGNORE']
      return matches if globignore.nil? || globignore.empty?
      patterns = globignore.split(':').reject(&:empty?)
      return matches if patterns.empty?
      matches = matches.reject { |m| m == '.' || m == '..' || m.end_with?('/.') || m.end_with?('/..') }
      matches.reject do |match|
        basename = File.basename(match)
        patterns.any? do |pattern|
          File.fnmatch?(pattern, basename, File::FNM_DOTMATCH) ||
            File.fnmatch?(pattern, match, File::FNM_DOTMATCH)
        end
      end
    end

    def apply_globsort(matches)
      return matches if matches.empty?
      globsort = ENV['GLOBSORT']
      return matches.sort if globsort.nil? || globsort.empty? || globsort == 'name'
      reverse = globsort.start_with?('-')
      sort_type = reverse ? globsort[1..] : globsort
      sorted = case sort_type
               when 'name' then matches.sort
               when 'nosort', 'none' then matches
               when 'size' then matches.sort_by { |f| File.exist?(f) ? File.size(f) : 0 }
               when 'mtime' then matches.sort_by { |f| File.exist?(f) ? File.mtime(f) : Time.at(0) }
               when 'atime' then matches.sort_by { |f| File.exist?(f) ? File.atime(f) : Time.at(0) }
               when 'ctime' then matches.sort_by { |f| File.exist?(f) ? File.ctime(f) : Time.at(0) }
               when 'extension' then matches.sort_by { |f| [File.extname(f), f] }
               else matches.sort
               end
      reverse ? sorted.reverse : sorted
    end

    def expand_prompt(ps)
      # Expand prompt escape sequences like \h, \u, \w, etc.
      return '' if ps.nil?

      result = +''
      i = 0

      while i < ps.length
        if ps[i] == '\\'
          i += 1
          break if i >= ps.length

          case ps[i]
          when 'a' then result << "\a"
          when 'd' then result << Time.now.strftime('%a %b %d')
          when 'D'
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              fmt_end = ps.index('}', i)
              if fmt_end
                fmt = ps[i...fmt_end]
                result << Time.now.strftime(fmt)
                i = fmt_end
              end
            else
              i -= 1
              result << 'D'
            end
          when 'e' then result << "\e"
          when 'h' then result << Socket.gethostname.split('.').first
          when 'H' then result << Socket.gethostname
          when 'j' then result << '0' # Job count - simplified
          when 'l' then result << (File.basename(`tty`.strip) rescue 'tty')
          when 'n' then result << "\n"
          when 'r' then result << "\r"
          when 's' then result << 'rubish'
          when 't' then result << Time.now.strftime('%H:%M:%S')
          when 'T' then result << Time.now.strftime('%I:%M:%S')
          when '@' then result << Time.now.strftime('%I:%M %p')
          when 'A' then result << Time.now.strftime('%H:%M')
          when 'u' then result << (ENV['USER'] || Etc.getlogin || 'user')
          when 'v' then result << Rubish::VERSION
          when 'V' then result << Rubish::VERSION
          when 'w'
            home = ENV['HOME'] || ''
            cwd = Dir.pwd
            display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
            result << display_path
          when 'W'
            cwd = Dir.pwd
            home = ENV['HOME'] || ''
            result << (cwd == home ? '~' : File.basename(cwd))
          when '!' then result << '1' # History number - simplified
          when '#' then result << '1' # Command number - simplified
          when '$' then result << (Process.uid == 0 ? '#' : '$')
          when '\\' then result << '\\'
          when '[' then nil # Ignore non-printing start
          when ']' then nil # Ignore non-printing end
          else result << '\\' << ps[i]
          end
        else
          result << ps[i]
        end
        i += 1
      end

      result
    end

    def format_timeformat(fmt, real, user, sys)
      result = +''
      i = 0
      while i < fmt.length
        if fmt[i] == '%'
          i += 1
          break if i >= fmt.length
          if fmt[i] == '%'
            result << '%'
            i += 1
            next
          end
          precision = 3
          if fmt[i] =~ /[0-9]/
            precision = fmt[i].to_i
            i += 1
          end
          long_format = false
          if i < fmt.length && fmt[i] == 'l'
            long_format = true
            i += 1
          end
          break if i >= fmt.length
          case fmt[i]
          when 'R' then result << format_time_value(real, precision, long_format)
          when 'U' then result << format_time_value(user, precision, long_format)
          when 'S' then result << format_time_value(sys, precision, long_format)
          when 'P'
            pct = real > 0 ? ((user + sys) / real * 100) : 0
            result << format("%.#{precision}f", pct)
          else
            result << '%' << fmt[i]
          end
          i += 1
        elsif fmt[i] == '\\'
          i += 1
          break if i >= fmt.length
          case fmt[i]
          when 'n' then result << "\n"
          when 't' then result << "\t"
          else result << fmt[i]
          end
          i += 1
        else
          result << fmt[i]
          i += 1
        end
      end
      result
    end

    def format_time_value(seconds, precision, long_format)
      if long_format
        mins = (seconds / 60).to_i
        secs = seconds % 60
        precision > 0 ? format('%dm%.*fs', mins, precision, secs) : format('%dm%ds', mins, secs.to_i)
      else
        precision > 0 ? format('%.*f', precision, seconds) : format('%d', seconds.to_i)
      end
    end

    def eval_cond_expr(parts, start_idx, end_idx)
      return true if start_idx >= end_idx
      tokens = parts[start_idx...end_idx]
      return true if tokens.empty?

      or_idx = find_logical_op(tokens, '||')
      if or_idx
        left = eval_cond_expr(tokens, 0, or_idx)
        return true if left
        return eval_cond_expr(tokens, or_idx + 1, tokens.length)
      end

      and_idx = find_logical_op(tokens, '&&')
      if and_idx
        left = eval_cond_expr(tokens, 0, and_idx)
        return false unless left
        return eval_cond_expr(tokens, and_idx + 1, tokens.length)
      end

      if tokens.first == '(' && tokens.last == ')'
        return eval_cond_expr(tokens[1...-1], 0, tokens.length - 2)
      end

      return !eval_cond_expr(tokens[1..], 0, tokens.length - 1) if tokens.first == '!'

      eval_cond_primary(tokens)
    end

    def find_logical_op(tokens, op)
      depth = 0
      tokens.each_with_index do |token, i|
        case token
        when '(' then depth += 1
        when ')' then depth -= 1
        when op then return i if depth == 0
        end
      end
      nil
    end

    def eval_cond_primary(tokens)
      return true if tokens.empty?
      return eval_unary_test(tokens[0], tokens[1]) if tokens.length == 2 && tokens[0].start_with?('-')
      return !tokens[0].to_s.empty? if tokens.length == 1
      return eval_binary_test(tokens[0], tokens[1], tokens[2]) if tokens.length == 3
      if tokens.length > 3
        tokens.each_with_index do |token, i|
          next if i == 0 || i == tokens.length - 1
          if %w[== != =~ < > -eq -ne -lt -le -gt -ge -nt -ot -ef].include?(token)
            left = tokens[0...i].join(' ')
            right_parts = tokens[i + 1..]
            # For regex (=~), reconstruct pattern without spaces around parens
            # For glob (== !=), also reconstruct to preserve extglob patterns
            right = if token == '=~'
                      reconstruct_regex_pattern(right_parts)
                    elsif token == '==' || token == '!='
                      reconstruct_glob_pattern(right_parts)
                    else
                      right_parts.join(' ')
                    end
            return eval_binary_test(left, token, right)
          end
        end
      end
      !tokens.join.empty?
    end

    def reconstruct_regex_pattern(parts)
      # Reconstruct regex pattern from tokenized parts
      # Parentheses and regex anchors should be directly attached (no spaces)
      result = +''
      regex_special = %w[( ) ^ $ * + ? | [ ] { }]
      parts.each_with_index do |part, i|
        if regex_special.include?(part)
          # Special regex characters don't get spaces around them
          result << part
        else
          # Add space before if previous wasn't a special char and result doesn't end with one
          prev_part = i > 0 ? parts[i - 1] : nil
          needs_space = i > 0 && !result.empty? && !regex_special.include?(prev_part) &&
                        !regex_special.any? { |s| result.end_with?(s) }
          result << ' ' if needs_space
          result << part
        end
      end
      result
    end

    def reconstruct_glob_pattern(parts)
      # Reconstruct glob pattern from tokenized parts
      # For extglob patterns like @(a|b), ?(x), *(y), +(z), !(w),
      # parentheses and pipe should be directly attached (no spaces)
      result = +''
      glob_special = %w[( ) |]
      parts.each_with_index do |part, i|
        if glob_special.include?(part)
          # Special glob characters don't get spaces around them
          result << part
        else
          prev_part = i > 0 ? parts[i - 1] : nil
          needs_space = i > 0 && !result.empty? && !glob_special.include?(prev_part) &&
                        !glob_special.any? { |s| result.end_with?(s) }
          result << ' ' if needs_space
          result << part
        end
      end
      result
    end

    def eval_unary_test(op, arg)
      case op
      when '-z' then arg.to_s.empty?
      when '-n' then !arg.to_s.empty?
      when '-e' then File.exist?(arg)
      when '-f' then File.file?(arg)
      when '-d' then File.directory?(arg)
      when '-r' then File.readable?(arg)
      when '-w' then File.writable?(arg)
      when '-x' then File.executable?(arg)
      when '-s' then File.exist?(arg) && File.size(arg) > 0
      when '-L', '-h' then File.symlink?(arg)
      when '-v' then ENV.key?(arg)
      else false
      end
    rescue
      false
    end

    def eval_binary_test(left, op, right)
      case op
      when '==' then cond_pattern_match?(left, right)
      when '!=' then !cond_pattern_match?(left, right)
      when '=~' then cond_regex_match?(left, right)
      when '<' then left.to_s < right.to_s
      when '>' then left.to_s > right.to_s
      when '-eq' then left.to_i == right.to_i
      when '-ne' then left.to_i != right.to_i
      when '-lt' then left.to_i < right.to_i
      when '-le' then left.to_i <= right.to_i
      when '-gt' then left.to_i > right.to_i
      when '-ge' then left.to_i >= right.to_i
      when '-nt' then File.exist?(left) && File.exist?(right) && File.mtime(left) > File.mtime(right)
      when '-ot' then File.exist?(left) && File.exist?(right) && File.mtime(left) < File.mtime(right)
      when '-ef' then File.exist?(left) && File.exist?(right) && File.stat(left).ino == File.stat(right).ino
      else false
      end
    rescue
      false
    end

    def cond_pattern_match?(string, pattern)
      # In [[ ]], == does glob pattern matching (not literal)
      # Handle extglob patterns when extglob is enabled
      if shopt_enabled?('extglob') && has_extglob?(pattern)
        # Convert extglob pattern to regex for matching
        base_regex = extglob_to_regex(pattern)
        if shopt_enabled?('nocasematch')
          regex = Regexp.new(base_regex.source, Regexp::IGNORECASE)
        else
          regex = base_regex
        end
        !!string.match?(regex)
      else
        # Use File.fnmatch for standard glob patterns
        flags = shopt_enabled?('nocasematch') ? File::FNM_CASEFOLD : 0
        File.fnmatch(pattern, string, File::FNM_EXTGLOB | flags)
      end
    end

    def has_extglob?(pattern)
      # Check if pattern contains extended glob operators: ?() *() +() @() !()
      pattern.match?(/[?*+@!]\([^)]*\)/)
    end

    def extglob_to_regex(pattern)
      # Convert extended glob pattern to Ruby regex
      result = +''
      i = 0

      while i < pattern.length
        char = pattern[i]

        case char
        when '\\'
          # Escape next character
          result << Regexp.escape(pattern[i + 1] || '')
          i += 2
        when '?'
          if pattern[i + 1] == '('
            # ?(pattern) - zero or one
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})?"
            i = end_idx + 1
          else
            # Regular ? glob - match any single character
            result << '.'
            i += 1
          end
        when '*'
          if pattern[i + 1] == '('
            # *(pattern) - zero or more
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})*"
            i = end_idx + 1
          else
            # Regular * glob - match any characters
            result << '.*'
            i += 1
          end
        when '+'
          if pattern[i + 1] == '('
            # +(pattern) - one or more
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})+"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '@'
          if pattern[i + 1] == '('
            # @(pattern) - exactly one
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?:#{extglob_alternatives_to_regex(inner)})"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '!'
          if pattern[i + 1] == '('
            # !(pattern) - anything except
            end_idx = find_matching_paren(pattern, i + 1)
            inner = pattern[i + 2...end_idx]
            result << "(?!#{extglob_alternatives_to_regex(inner)}).*"
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '['
          # Character class - find the closing ]
          end_idx = pattern.index(']', i + 1)
          if end_idx
            result << pattern[i..end_idx]
            i = end_idx + 1
          else
            result << Regexp.escape(char)
            i += 1
          end
        when '.'
          result << '\\.'
          i += 1
        else
          result << Regexp.escape(char)
          i += 1
        end
      end

      Regexp.new("\\A#{result}\\z")
    end

    def extglob_alternatives_to_regex(inner)
      # Convert pipe-separated alternatives to regex alternatives
      alternatives = split_extglob_alternatives(inner)
      alternatives.map { |alt| extglob_simple_to_regex(alt) }.join('|')
    end

    def split_extglob_alternatives(inner)
      # Split on | but respect nested parentheses
      result = []
      current = +''
      depth = 0

      inner.each_char do |char|
        case char
        when '('
          depth += 1
          current << char
        when ')'
          depth -= 1
          current << char
        when '|'
          if depth == 0
            result << current
            current = +''
          else
            current << char
          end
        else
          current << char
        end
      end
      result << current unless current.empty?
      result
    end

    def extglob_simple_to_regex(pattern)
      # Convert simple glob pattern (inside extglob parens) to regex
      result = +''
      i = 0

      while i < pattern.length
        char = pattern[i]
        case char
        when '*'
          result << '.*'
        when '?'
          result << '.'
        when '['
          end_idx = pattern.index(']', i + 1)
          if end_idx
            result << pattern[i..end_idx]
            i = end_idx
          else
            result << Regexp.escape(char)
          end
        when '.'
          result << '\\.'
        else
          result << Regexp.escape(char)
        end
        i += 1
      end
      result
    end

    def find_matching_paren(str, start_idx)
      depth = 0
      i = start_idx
      while i < str.length
        case str[i]
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      str.length
    end

    def cond_regex_match?(string, pattern)
      # Apply nocasematch option for case-insensitive matching
      regex_opts = shopt_enabled?('nocasematch') ? Regexp::IGNORECASE : 0
      regex = Regexp.new(pattern, regex_opts)
      match = regex.match(string)
      if match
        set_array('RUBISH_REMATCH', match.to_a)
        true
      else
        set_array('RUBISH_REMATCH', [])
        false
      end
    rescue RegexpError
      false
    end

    def allocate_varname_fd
      fd = @next_varname_fd
      @next_varname_fd += 1
      while @varname_fds.values.any? { |info| info[:fd] == @next_varname_fd }
        @next_varname_fd += 1
      end
      fd
    end

    def expand_heredoc_content(content)
      expand_string_content(content)
    end

    def perform_varname_redirect(fd_num, io, &block)
      result = block.call
      @varname_fds.each do |name, info|
        if info[:fd] == fd_num
          info[:io] = io
          break
        end
      end
      result
    end

    def expand_braces(str)
      # Find the first brace group to expand
      # Return array of expanded strings
      return [str] unless str.include?('{')

      # Find matching braces, handling nesting
      start_idx = nil
      depth = 0
      i = 0

      while i < str.length
        case str[i]
        when '\\'
          i += 2  # Skip escaped character
          next
        when '{'
          start_idx = i if depth == 0
          depth += 1
        when '}'
          depth -= 1
          if depth == 0 && start_idx
            # Found a complete brace group
            prefix = str[0...start_idx]
            suffix = str[i + 1..]
            content = str[start_idx + 1...i]

            # Check if it's a sequence {a..b}, {a..b..step} or a list {a,b,c}
            expansions = if content =~ /\A(-?\d+)\.\.(-?\d+)\.\.(-?\d+)\z/
                           expand_numeric_sequence($1, $2, $3.to_i)
                         elsif content =~ /\A(-?\d+)\.\.(-?\d+)\z/
                           expand_numeric_sequence($1, $2)
                         elsif content =~ /\A([a-zA-Z])\.\.([a-zA-Z])\.\.(-?\d+)\z/
                           expand_letter_sequence($1, $2, $3.to_i)
                         elsif content =~ /\A([a-zA-Z])\.\.([a-zA-Z])\z/
                           expand_letter_sequence($1, $2)
                         elsif content.include?(',')
                           expand_brace_list(content)
                         else
                           # Not a valid brace expansion, return as-is
                           return [str]
                         end

            # Combine prefix, expansions, suffix and recursively expand
            results = []
            expansions.each do |exp|
              combined = "#{prefix}#{exp}#{suffix}"
              results.concat(expand_braces(combined))
            end
            return results
          end
        end
        i += 1
      end

      # No complete brace group found
      [str]
    end

    def expand_numeric_sequence(start_str, end_str, step = nil)
      start_val = start_str.to_i
      end_val = end_str.to_i

      # Check for zero-padding
      width = if start_str.start_with?('0') || start_str.start_with?('-0')
                start_str.sub(/^-/, '').length
              elsif end_str.start_with?('0') || end_str.start_with?('-0')
                end_str.sub(/^-/, '').length
              else
                0
              end

      # Determine step (use absolute value, direction is determined by start/end)
      step = step&.abs || 1
      step = 1 if step == 0  # Prevent infinite loop

      # Generate sequence
      result = []
      if start_val <= end_val
        n = start_val
        while n <= end_val
          result << n
          n += step
        end
      else
        n = start_val
        while n >= end_val
          result << n
          n -= step
        end
      end

      result.map do |n|
        if width > 0
          format("%0#{width}d", n)
        else
          n.to_s
        end
      end
    end

    def expand_letter_sequence(start_char, end_char, step = nil)
      step = step&.abs || 1
      step = 1 if step == 0  # Prevent infinite loop

      result = []
      if start_char <= end_char
        c = start_char
        while c <= end_char
          result << c
          c = (c.ord + step).chr
        end
      else
        c = start_char
        while c >= end_char
          result << c
          c = (c.ord - step).chr
        end
      end
      result
    end

    def expand_brace_list(content)
      # Split on commas, but respect nested braces
      items = []
      current = +''
      depth = 0

      content.each_char do |char|
        case char
        when '{'
          depth += 1
          current << char
        when '}'
          depth -= 1
          current << char
        when ','
          if depth == 0
            items << current
            current = +''
          else
            current << char
          end
        else
          current << char
        end
      end
      items << current unless current.empty?

      # Recursively expand any nested braces in items
      items.flat_map { |item| expand_braces(item) }
    end

    # Callback accessor delegates to state
    def executor
      @state.executor
    end

    def executor=(value)
      @state.executor = value
    end

    def function_checker
      @state.function_checker
    end

    def function_checker=(value)
      @state.function_checker = value
    end

    def function_getter
      @state.function_getter
    end

    def function_getter=(value)
      @state.function_getter = value
    end

    def function_remover
      @state.function_remover
    end

    def function_remover=(value)
      @state.function_remover = value
    end

    def function_lister
      @state.function_lister
    end

    def function_lister=(value)
      @state.function_lister = value
    end

    def source_file_getter
      @state.source_file_getter
    end

    def source_file_getter=(value)
      @state.source_file_getter = value
    end

    def define_prompt_function(name, code)
      # Stub - prompt functions are stored in REPL's @functions
      @functions[name] = {
        block: -> { instance_eval(code) },
        source: nil,
        source_code: code,
        lineno: 0
      }
    end

    public

    include Arithmetic
    include Expansion
    include Runtime
    include Builtins
  end
end
