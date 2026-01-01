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
      line = expand_variables(line)
      tokens = @lexer_class.new(line).tokenize
      ast = @parser_class.new(tokens).parse
      return unless ast

      # Check for builtins (simple command only)
      if ast.is_a?(AST::Command) && Builtins.builtin?(ast.name)
        result = Builtins.run(ast.name, ast.args)
        @last_status = result ? 0 : 1
        return
      end

      code = @codegen.generate(ast)
      result = eval_in_context(code)
      @last_status = extract_exit_status(result)
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

    def expand_variables(line)
      # Expand ${VAR} and $VAR (but not inside single quotes)
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
        elsif char == '$' && !in_single_quotes
          if line[i + 1] == '?'
            # Special variable $? - last exit status
            result << @last_status.to_s
            i += 2
          elsif line[i + 1] == '$'
            # Special variable $$ - current shell PID
            result << Process.pid.to_s
            i += 2
          elsif line[i + 1] == '!'
            # Special variable $! - last background PID
            result << (@last_bg_pid ? @last_bg_pid.to_s : '')
            i += 2
          elsif line[i + 1] == '0'
            # Special variable $0 - script/shell name
            result << @script_name
            i += 2
          elsif line[i + 1] =~ /[1-9]/
            # Positional parameters $1-$9
            idx = line[i + 1].to_i - 1
            result << (@positional_params[idx] || '')
            i += 2
          elsif line[i + 1] == '('
            # Command substitution $(cmd)
            depth = 1
            j = i + 2
            while j < line.length && depth > 0
              if line[j] == '('
                depth += 1
              elsif line[j] == ')'
                depth -= 1
              end
              j += 1
            end
            if depth == 0
              cmd = line[i + 2...j - 1]
              output = `#{cmd}`.chomp
              result << output
              i = j
            else
              result << char
              i += 1
            end
          elsif line[i + 1] == '{'
            # ${VAR} form
            end_brace = line.index('}', i + 2)
            if end_brace
              var_name = line[i + 2...end_brace]
              result << ENV.fetch(var_name, '')
              i = end_brace + 1
            else
              result << char
              i += 1
            end
          elsif line[i + 1] =~ /[a-zA-Z_]/
            # $VAR form
            j = i + 1
            j += 1 while j < line.length && line[j] =~ /[a-zA-Z0-9_]/
            var_name = line[i + 1...j]
            result << ENV.fetch(var_name, '')
            i = j
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
