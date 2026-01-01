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
      Builtins.executor = ->(line) { execute(line) }
      Builtins.script_name_getter = -> { @script_name }
      Builtins.script_name_setter = ->(name) { @script_name = name }
      Builtins.positional_params_getter = -> { @positional_params }
      Builtins.positional_params_setter = ->(params) { @positional_params = params }
    end

    attr_accessor :script_name, :positional_params

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
      line = Builtins.expand_alias(line)
      line = expand_tilde(line)
      # Variable expansion now happens at runtime in generated Ruby code
      tokens = @lexer_class.new(line).tokenize
      ast = @parser_class.new(tokens).parse
      return unless ast

      # Check for builtins (simple command only)
      if ast.is_a?(AST::Command) && Builtins.builtin?(ast.name)
        # Expand variables in args for builtins
        expanded_args = expand_args_for_builtin(ast.args)
        result = Builtins.run(ast.name, expanded_args)
        @last_status = result ? 0 : 1
        return
      end

      code = @codegen.generate(ast)
      result = eval_in_context(code)
      @last_status = extract_exit_status(result)
    end

    def expand_args_for_builtin(args)
      args.map { |arg| expand_single_arg(arg) }
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
      when Command, Pipeline
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

    def eval_in_context(code)
      result = binding.eval(code)
      result.run if result.is_a?(Command) || result.is_a?(Pipeline)
      result
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

    # Builtins that must run in current process (affect shell state)
    PROCESS_BUILTINS = %w[cd export set shift source . return exit].freeze

    def __run_cmd(&block)
      result = block.call
      if result.is_a?(Command) && PROCESS_BUILTINS.include?(result.name)
        # Run process-affecting builtins directly in current process
        success = Builtins.run(result.name, result.args)
        @last_status = success ? 0 : 1
        result
      else
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
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
