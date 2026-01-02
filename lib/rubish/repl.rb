# frozen_string_literal: true

module Rubish
  class REPL
    def initialize
      @lexer_class = Lexer
      @parser_class = Parser
      @codegen = Codegen.new
      @last_line = nil
      @last_status = 0
      @last_bg_pid = nil
      @script_name = 'rubish'
      @positional_params = []
      @functions = {}
      @heredoc_content = nil  # Content for current heredoc
      Builtins.executor = ->(line) { execute(line) }
      Builtins.script_name_getter = -> { @script_name }
      Builtins.script_name_setter = ->(name) { @script_name = name }
      Builtins.positional_params_getter = -> { @positional_params }
      Builtins.positional_params_setter = ->(params) { @positional_params = params }
      Builtins.function_checker = ->(name) { @functions.key?(name) }
      Builtins.heredoc_content_setter = ->(content) { @heredoc_content = content }
      # Set up Command class to handle functions in pipelines
      Command.function_checker = ->(name) { @functions.key?(name) }
      Command.function_caller = ->(name, args) { call_function(name, args) }
    end

    attr_accessor :script_name, :positional_params, :functions

    def run
      setup_reline
      setup_signals
      load_config
      exit_code = catch(:exit) do
        loop { process_line }
      end
      exit_code
    end

    private

    def setup_reline
      Reline.completion_proc = ->(input) { complete(input) }
    end

    def setup_signals
      # Ignore SIGINT and SIGTSTP in the shell itself
      # They should only affect foreground jobs
      trap('INT') { puts }   # Just print newline on Ctrl+C
      trap('TSTP') { }       # Ignore Ctrl+Z for shell
    end

    def load_config
      config_file = File.expand_path('~/.rubishrc')
      return unless File.exist?(config_file)

      File.readlines(config_file, chomp: true).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')

        begin
          execute(line)
        rescue => e
          puts "rubishrc: #{e.message}"
        end
      end
    end

    def prompt
      "#{Dir.pwd.sub(ENV['HOME'], '~')}$ "
    end

    def process_line
      # Check for completed background jobs
      JobManager.instance.check_background_jobs

      line = Reline.readline(prompt, true)
      return throw(:exit, 0) unless line

      line = line.strip
      return if line.empty?

      @last_line = line
      execute(line)
    rescue Interrupt
      puts
    rescue => e
      puts "rubish: #{e.message}"
    end

    def execute(line)
      line, expanded = expand_history(line)
      return unless line

      # Print expanded command if history expansion occurred
      puts line if expanded

      line = Builtins.expand_alias(line)
      line = expand_tilde(line)
      # Variable expansion now happens at runtime in generated Ruby code
      tokens = @lexer_class.new(line).tokenize
      ast = @parser_class.new(tokens).parse
      return unless ast

      # Check for heredocs and collect content if needed
      # Skip if content was already set (e.g., by source command)
      if (heredoc = find_heredoc(ast)) && @heredoc_content.nil?
        @heredoc_content = collect_heredoc_content(heredoc.delimiter, heredoc.strip_tabs)
      end

      # Check for builtins (simple command only)
      if ast.is_a?(AST::Command) && Builtins.builtin?(ast.name)
        # Expand variables in args for builtins
        expanded_args = expand_args_for_builtin(ast.args)
        result = Builtins.run(ast.name, expanded_args)
        @last_status = result ? 0 : 1
        return
      end

      # Check for user-defined functions (simple command only)
      if ast.is_a?(AST::Command) && @functions.key?(ast.name)
        expanded_args = expand_args_for_builtin(ast.args)
        result = call_function(ast.name, expanded_args)
        @last_status = result ? 0 : 1
        return
      end

      code = @codegen.generate(ast)
      result = eval_in_context(code)
      @last_status = extract_exit_status(result)
    ensure
      @heredoc_content = nil
    end

    def call_function(name, args)
      func = @functions[name]
      return false unless func

      # Save current positional params and set new ones
      saved_params = @positional_params
      @positional_params = args

      begin
        result = func.call
        # Handle return value
        if result.is_a?(Command) || result.is_a?(Pipeline)
          result.success?
        else
          true
        end
      rescue LocalJumpError
        # return was called in function
        true
      ensure
        @positional_params = saved_params
      end
    end

    def expand_args_for_builtin(args)
      args.flat_map { |arg| expand_single_arg_with_brace_and_glob(arg) }
    end

    def expand_single_arg_with_brace_and_glob(arg)
      return [arg] unless arg.is_a?(String)

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return [arg[1...-1]]
      end

      # Double-quoted strings: strip quotes, expand variables, no glob/brace
      if arg.start_with?('"') && arg.end_with?('"')
        return [expand_string_content(arg[1...-1])]
      end

      # Brace expansion first (before variable expansion in shell, but we do it after for simplicity)
      # Expand braces first
      brace_expanded = if arg.include?('{') && !arg.start_with?('$')
                         expand_braces(arg)
                       else
                         [arg]
                       end

      # Then expand variables and globs on each result
      brace_expanded.flat_map do |item|
        expanded = expand_string_content(item)
        # Then expand globs if present
        if expanded.match?(/[*?\[]/)
          __glob(expanded)
        else
          [expanded]
        end
      end
    end

    def expand_single_arg_with_glob(arg)
      return [arg] unless arg.is_a?(String)

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return [arg[1...-1]]
      end

      # Double-quoted strings: strip quotes, expand variables, no glob
      if arg.start_with?('"') && arg.end_with?('"')
        return [expand_string_content(arg[1...-1])]
      end

      # Unquoted: expand variables first
      expanded = expand_string_content(arg)

      # Then expand globs if present
      if expanded.match?(/[*?\[]/)
        __glob(expanded)
      else
        [expanded]
      end
    end

    def expand_single_arg(arg)
      return arg unless arg.is_a?(String)

      # Single-quoted strings: no expansion, strip quotes
      if arg.start_with?("'") && arg.end_with?("'")
        return arg[1...-1]
      end

      # Double-quoted strings: strip quotes, expand variables
      if arg.start_with?('"') && arg.end_with?('"')
        return expand_string_content(arg[1...-1])
      end

      # Unquoted: expand variables
      expand_string_content(arg)
    end

    def expand_string_content(str)
      result = +''
      i = 0

      while i < str.length
        char = str[i]

        if char == '\\'
          # Escape sequence
          result << str[i + 1] if i + 1 < str.length
          i += 2
        elsif char == '$'
          expanded, consumed = expand_variable_at(str, i)
          if consumed > 0
            result << expanded
            i += consumed
          else
            result << char
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      result
    end

    def expand_variable_at(str, pos)
      return ['', 0] unless str[pos] == '$'

      # Arithmetic expansion $((...))
      if str[pos + 1] == '(' && str[pos + 2] == '('
        depth = 2
        j = pos + 3
        while j < str.length && depth > 0
          if str[j] == '('
            depth += 1
          elsif str[j] == ')'
            depth -= 1
          end
          j += 1
        end
        if depth == 0
          expr = str[pos + 3...j - 2]
          return [__arith(expr), j - pos]
        end
        return ['', 0]
      end

      # Command substitution $(...)
      if str[pos + 1] == '('
        depth = 1
        j = pos + 2
        while j < str.length && depth > 0
          j += 1 and next if str[j] == '('  && (depth += 1)
          j += 1 and next if str[j] == ')'  && (depth -= 1) > 0
          break if depth == 0
          j += 1
        end
        if depth == 0
          cmd = str[pos + 2...j]
          return [`#{cmd}`.chomp, j - pos + 1]
        end
        return ['', 0]
      end

      # Special variables
      two_char = str[pos, 2]
      case two_char
      when '$?'
        return [@last_status.to_s, 2]
      when '$$'
        return [Process.pid.to_s, 2]
      when '$!'
        return [@last_bg_pid ? @last_bg_pid.to_s : '', 2]
      when '$0'
        return [@script_name, 2]
      when '$#'
        return [@positional_params.length.to_s, 2]
      when '$@', '$*'
        return [@positional_params.join(' '), 2]
      end

      if str[pos + 1] =~ /[1-9]/
        n = str[pos + 1].to_i
        return [@positional_params[n - 1] || '', 2]
      end

      # ${VAR} form
      if str[pos + 1] == '{'
        end_brace = str.index('}', pos + 2)
        if end_brace
          var_name = str[pos + 2...end_brace]
          return [ENV.fetch(var_name, ''), end_brace - pos + 1]
        end
      end

      # $VAR form
      if str[pos + 1] =~ /[a-zA-Z_]/
        j = pos + 1
        j += 1 while j < str.length && str[j] =~ /[a-zA-Z0-9_]/
        var_name = str[pos + 1...j]
        return [ENV.fetch(var_name, ''), j - pos]
      end

      ['', 0]
    end

    def extract_exit_status(result)
      case result
      when Command, Pipeline, Subshell, HeredocCommand
        result.status&.exitstatus || 0
      when Integer
        result
      else
        0
      end
    end

    def expand_tilde(line)
      # Expand ~ and ~user (but not inside single quotes)
      result = +''
      i = 0
      in_single_quotes = false
      in_double_quotes = false

      while i < line.length
        char = line[i]

        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          result << char
          i += 1
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          result << char
          i += 1
        elsif char == '~' && !in_single_quotes
          # Check if ~ is at start of a word (preceded by space, start, or quotes)
          prev_char = i > 0 ? line[i - 1] : nil
          at_word_start = prev_char.nil? || prev_char =~ /[\s"'=:]/

          if at_word_start
            next_char = line[i + 1]
            # Check for special ~+ (PWD) and ~- (OLDPWD)
            if next_char == '+' && (line[i + 2].nil? || line[i + 2] =~ %r{[\s/]})
              result << (ENV['PWD'] || Dir.pwd)
              i += 2
            elsif next_char == '-' && (line[i + 2].nil? || line[i + 2] =~ %r{[\s/]})
              if ENV['OLDPWD']
                result << ENV['OLDPWD']
              else
                result << '~-'  # Keep literal if OLDPWD not set
              end
              i += 2
            else
              # Look for username after ~
              j = i + 1
              j += 1 while j < line.length && line[j] =~ /[a-zA-Z0-9_-]/

              if j == i + 1
                # Just ~ or ~/path
                result << Dir.home
                i = j
              else
                # ~username
                username = line[i + 1...j]
                begin
                  result << Dir.home(username)
                rescue ArgumentError
                  # Unknown user, keep literal
                  result << line[i...j]
                end
                i = j
              end
            end
          else
            result << char
            i += 1
          end
        else
          result << char
          i += 1
        end
      end

      result
    end

    def expand_history(line)
      # History expansion with word designators and modifiers
      # Format: !event[:word][:modifier...]
      # Returns [expanded_line, was_expanded]
      return [line, false] unless line.include?('!') || line.start_with?('^')

      history = Reline::HISTORY.to_a
      return [line, false] if history.empty?

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
              return [last_cmd.sub(old_str, new_str), true]
            else
              puts 'rubish: substitution failed'
              return [nil, false]
            end
          end
        end

        if char == '!' && !in_single_quotes
          expansion, consumed, error, is_print_only = parse_history_expansion(line, i, history)
          if error
            puts error
            return [nil, false]
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
        return [nil, false]
      end

      [result, expanded]
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

    def eval_in_context(code)
      result = binding.eval(code)
      if result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function, handling redirects
        call_function_with_redirects(result)
      elsif result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell) || result.is_a?(HeredocCommand)
        result.run
      end
      result
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

    def __cmd(name, *args, &block)
      Command.new(name, *args, &block)
    end

    def __and_cmd(left_proc, right_proc)
      left = left_proc.call
      left.run if left.is_a?(Command) || left.is_a?(Pipeline)
      return left unless left.success?

      right = right_proc.call
      right.run if right.is_a?(Command) || right.is_a?(Pipeline)
      right
    end

    def __or_cmd(left_proc, right_proc)
      left = left_proc.call
      left.run if left.is_a?(Command) || left.is_a?(Pipeline)
      return left if left.success?

      right = right_proc.call
      right.run if right.is_a?(Command) || right.is_a?(Pipeline)
      right
    end

    def __background(&block)
      # Fork and run in background
      pid = fork do
        # Reset signal handlers in child
        trap('INT', 'DEFAULT')
        trap('TSTP', 'DEFAULT')

        # Create new process group
        Process.setpgid(0, 0)

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        exit(0)
      end

      # Parent: create job and return immediately
      Process.setpgid(pid, pid) rescue nil  # May fail if child already set it
      @last_bg_pid = pid
      job = JobManager.instance.add(
        pid: pid,
        pgid: pid,
        command: @last_line
      )
      puts "[#{job.id}] #{pid}"
      nil
    end

    def __condition(&block)
      result = block.call
      if result.is_a?(Command) && Builtins.builtin?(result.name)
        # Run builtin directly and check its return value
        Builtins.run(result.name, result.args)
      else
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        result.success?
      end
    end

    def __for_loop(variable, items, &block)
      items.each do |item|
        ENV[variable] = item
        block.call
      end
    end

    def __arith(expr)
      # Evaluate arithmetic expression
      # Replace variable references with their values
      expanded = expr.gsub(/\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $1
          # ${VAR} form
          ENV.fetch($1, '0')
        elsif $2
          # $VAR form
          ENV.fetch($2, '0')
        elsif $3
          # Plain variable name (only if it looks like a variable, not an operator)
          # Check if it's a known variable, otherwise keep as-is (might be a function name)
          ENV.key?($3) ? ENV[$3] : match
        else
          match
        end
      end

      # Evaluate the expression safely (only allow arithmetic)
      # Convert shell operators to Ruby: ** for exponentiation is same
      # Note: bash uses ** for exponent, which Ruby also supports
      begin
        result = eval(expanded)
        result.to_s
      rescue StandardError
        '0'
      end
    end

    def __param_expand(var_name, operator, operand)
      # Parameter expansion operations
      value = ENV[var_name]
      is_set = ENV.key?(var_name)
      is_null = value.nil? || value.empty?

      case operator
      when ':-'
        # ${var:-default} - use default if unset or null
        is_null ? operand : value
      when ':='
        # ${var:=default} - assign default if unset or null
        if is_null
          ENV[var_name] = operand
          operand
        else
          value
        end
      when ':+'
        # ${var:+value} - use value if set and non-null
        is_null ? '' : operand
      when ':?'
        # ${var:?message} - error if unset or null
        if is_null
          msg = operand.empty? ? "#{var_name}: parameter null or not set" : operand
          raise msg
        end
        value
      when '#'
        # ${var#pattern} - remove shortest prefix
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :shortest).match(value) do |m|
          value[m.end(0)..]
        end || value
      when '##'
        # ${var##pattern} - remove longest prefix
        return '' if value.nil?
        pattern_to_regex(operand, :prefix, :longest).match(value) do |m|
          value[m.end(0)..]
        end || value
      when '%'
        # ${var%pattern} - remove shortest suffix
        return '' if value.nil?
        remove_suffix(value, operand, :shortest)
      when '%%'
        # ${var%%pattern} - remove longest suffix
        return '' if value.nil?
        remove_suffix(value, operand, :longest)
      else
        value || ''
      end
    end

    def __param_length(var_name)
      # ${#var} - length of variable value
      (ENV[var_name] || '').length.to_s
    end

    def __param_substring(var_name, offset, length)
      # ${var:offset} or ${var:offset:length}
      value = ENV[var_name] || ''
      offset = offset.to_i
      if length
        length = length.to_i
        if length < 0
          # Negative length means from end
          value[offset...length]
        else
          value[offset, length]
        end
      else
        value[offset..]
      end || ''
    end

    def remove_suffix(value, pattern, mode)
      # For suffix removal, we need to find where the pattern matches at the end
      # For shortest (%), we want the rightmost match start position
      # For longest (%%), we want the leftmost match start position
      # The regex must match the ENTIRE suffix (anchored at both ends)
      regex = pattern_to_regex(pattern, :full, mode)

      if mode == :shortest
        # Try matching from the end, progressively looking for shorter matches
        (value.length - 1).downto(0) do |i|
          if regex.match?(value[i..])
            return value[0...i]
          end
        end
        value  # No match
      else
        # For longest, find the earliest position where pattern matches to end
        (0...value.length).each do |i|
          if regex.match?(value[i..])
            return value[0...i]
          end
        end
        value  # No match
      end
    end

    def pattern_to_regex(pattern, position, greedy)
      # Convert shell glob pattern to regex
      # * -> .* or .*?
      # ? -> .
      # [...] -> [...]
      regex_str = +''
      i = 0
      while i < pattern.length
        char = pattern[i]
        case char
        when '*'
          regex_str << (greedy == :longest ? '.*' : '.*?')
        when '?'
          regex_str << '.'
        when '['
          # Find matching ]
          j = i + 1
          j += 1 if j < pattern.length && pattern[j] == '!'
          j += 1 if j < pattern.length && pattern[j] == ']'
          j += 1 while j < pattern.length && pattern[j] != ']'
          if j < pattern.length
            bracket = pattern[i..j]
            bracket = bracket.sub('[!', '[^')  # Convert [! to [^
            regex_str << bracket
            i = j
          else
            regex_str << Regexp.escape(char)
          end
        else
          regex_str << Regexp.escape(char)
        end
        i += 1
      end

      case position
      when :prefix
        Regexp.new("\\A#{regex_str}")
      when :suffix
        Regexp.new("#{regex_str}\\z")
      when :full
        Regexp.new("\\A#{regex_str}\\z")
      else
        Regexp.new(regex_str)
      end
    end

    def __glob(pattern)
      # Expand glob pattern, return original if no matches
      matches = Dir.glob(pattern)
      matches.empty? ? [pattern] : matches
    end

    def __proc_sub(command, direction)
      # Process substitution: <(cmd) or >(cmd)
      # Creates a named pipe and returns its path
      # The command runs in background, reading from or writing to the pipe

      # Create a unique FIFO path
      fifo_path = File.join(Dir.tmpdir, "rubish_procsub_#{$$}_#{rand(1000000)}")
      system('mkfifo', fifo_path)

      # Track the FIFO for cleanup
      @proc_sub_fifos ||= []
      @proc_sub_fifos << fifo_path

      if direction == :in
        # <(cmd) - command output becomes readable file
        # Fork a process to run the command and write to FIFO
        pid = fork do
          # Redirect stdout to the FIFO
          fifo = File.open(fifo_path, 'w')
          $stdout.reopen(fifo)
          $stderr.reopen('/dev/null', 'w')

          # Execute the command via shell
          exec('/bin/sh', '-c', command)
        end
        Process.detach(pid)
      else
        # >(cmd) - writable file whose content goes to command stdin
        # Fork a process to read from FIFO and pipe to command
        pid = fork do
          # Read from FIFO and pipe to command
          fifo = File.open(fifo_path, 'r')
          $stdin.reopen(fifo)
          $stderr.reopen('/dev/null', 'w')

          # Execute the command via shell
          exec('/bin/sh', '-c', command)
        end
        Process.detach(pid)
      end

      fifo_path
    end

    def cleanup_proc_sub_fifos
      return unless @proc_sub_fifos

      @proc_sub_fifos.each do |fifo|
        File.unlink(fifo) if File.exist?(fifo)
      rescue Errno::ENOENT
        # Already deleted
      end
      @proc_sub_fifos.clear
    end

    def __brace(pattern)
      # Expand brace patterns like {a,b,c} or {1..5}
      expand_braces(pattern)
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

            # Check if it's a sequence {a..b} or a list {a,b,c}
            expansions = if content =~ /\A(-?\d+)\.\.(-?\d+)\z/
                           expand_numeric_sequence($1, $2)
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

    def expand_numeric_sequence(start_str, end_str)
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

      range = start_val <= end_val ? (start_val..end_val) : (end_val..start_val).to_a.reverse
      range.map do |n|
        if width > 0
          format("%0#{width}d", n)
        else
          n.to_s
        end
      end
    end

    def expand_letter_sequence(start_char, end_char)
      if start_char <= end_char
        (start_char..end_char).to_a
      else
        (end_char..start_char).to_a.reverse
      end
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

    def __case_match(pattern, word)
      # Shell pattern matching using fnmatch
      # Supports *, ?, [...] patterns
      File.fnmatch(pattern, word, File::FNM_EXTGLOB)
    end

    def __subshell(&block)
      # Create a Subshell object that can be run, redirected, or piped
      Subshell.new(&block)
    end

    def __heredoc(delimiter, expand, strip_tabs, &block)
      content = @heredoc_content || ''

      # Apply tab stripping if <<- was used
      if strip_tabs
        content = content.lines.map { |l| l.sub(/\A\t+/, '') }.join
      end

      # Apply variable expansion if not quoted
      if expand
        content = expand_heredoc_content(content)
      end

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, &block)
    end

    def __herestring(string, &block)
      # Herestring provides a single string as stdin (with trailing newline)
      content = "#{string}\n"

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, &block)
    end

    def expand_heredoc_content(content)
      # Expand variables in heredoc content
      expand_string_content(content)
    end

    def find_heredoc(ast)
      case ast
      when AST::Heredoc
        ast
      when AST::Redirect
        find_heredoc(ast.command)
      when AST::Pipeline
        ast.commands.each do |cmd|
          if (h = find_heredoc(cmd))
            return h
          end
        end
        nil
      when AST::List
        ast.commands.each do |cmd|
          if (h = find_heredoc(cmd))
            return h
          end
        end
        nil
      else
        nil
      end
    end

    def collect_heredoc_content(delimiter, strip_tabs)
      lines = []
      loop do
        line = Reline.readline('> ', false)
        break unless line

        # Check for delimiter (possibly with leading tabs if strip_tabs)
        check_line = strip_tabs ? line.sub(/\A\t+/, '') : line
        if check_line.chomp == delimiter
          break
        end

        lines << line
      end
      lines.join("\n") + (lines.empty? ? '' : "\n")
    end

    def __define_function(name, &block)
      @functions[name] = block
      nil
    end

    # Builtins that must run in current process (affect shell state)
    PROCESS_BUILTINS = %w[cd export set shift source . return exit break continue].freeze

    def __run_cmd(&block)
      result = block.call
      if result.is_a?(Command) && PROCESS_BUILTINS.include?(result.name)
        # Run process-affecting builtins directly in current process
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        result
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function with redirects
        call_function_with_redirects(result)
        result
      else
        result.run if result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell)
        result
      end
    end

    def complete(input)
      line = Reline.line_buffer
      is_first_word = !line.include?(' ') || line.end_with?('| ')

      if is_first_word
        complete_command(input)
      else
        complete_file(input)
      end
    end

    def complete_command(input)
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
      Dir.glob("#{input}*").map do |f|
        File.directory?(f) ? "#{f}/" : f
      end.sort
    end
  end
end
