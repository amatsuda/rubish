# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w[cd exit jobs fg bg export pwd history alias unalias source . shift set return read].freeze

    @aliases = {}
    @executor = nil
    @script_name_getter = nil
    @script_name_setter = nil
    @positional_params_getter = nil
    @positional_params_setter = nil

    class << self
      attr_reader :aliases
      attr_accessor :executor, :script_name_getter, :script_name_setter, :positional_params_getter, :positional_params_setter
    end

    def self.builtin?(name)
      COMMANDS.include?(name)
    end

    def self.run(name, args)
      case name
      when 'cd'
        run_cd(args)
      when 'exit'
        run_exit(args)
      when 'jobs'
        run_jobs(args)
      when 'fg'
        run_fg(args)
      when 'bg'
        run_bg(args)
      when 'export'
        run_export(args)
      when 'pwd'
        run_pwd(args)
      when 'history'
        run_history(args)
      when 'alias'
        run_alias(args)
      when 'unalias'
        run_unalias(args)
      when 'source', '.'
        run_source(args)
      when 'shift'
        run_shift(args)
      when 'set'
        run_set(args)
      when 'return'
        run_return(args)
      when 'read'
        run_read(args)
      else
        false
      end
    end

    def self.run_cd(args)
      dir = args.first || ENV['HOME']
      Dir.chdir(dir)
      true
    rescue Errno::ENOENT => e
      puts "cd: #{e.message}"
      false
    end

    def self.run_export(args)
      if args.empty?
        # List all environment variables
        ENV.each { |k, v| puts "#{k}=#{v}" }
      else
        args.each do |arg|
          if arg.include?('=')
            key, value = arg.split('=', 2)
            ENV[key] = value
          else
            # Just export existing variable (no-op in this simple impl)
            puts "export: #{arg}=#{ENV[arg]}" if ENV.key?(arg)
          end
        end
      end
      true
    end

    def self.run_pwd(_args)
      puts Dir.pwd
      true
    end

    def self.run_history(args)
      history = Reline::HISTORY.to_a
      count = args.first&.to_i || history.length

      start_index = [history.length - count, 0].max
      history[start_index..].each_with_index do |line, i|
        puts format('%5d  %s', start_index + i + 1, line)
      end
      true
    end

    def self.run_alias(args)
      if args.empty?
        # List all aliases
        @aliases.each { |name, value| puts "alias #{name}='#{value}'" }
      else
        args.each do |arg|
          if arg.include?('=')
            name, value = arg.split('=', 2)
            # Remove surrounding quotes if present
            value = value.sub(/\A(['"])(.*)\1\z/, '\2')
            @aliases[name] = value
          else
            # Show specific alias
            if @aliases.key?(arg)
              puts "alias #{arg}='#{@aliases[arg]}'"
            else
              puts "alias: #{arg}: not found"
            end
          end
        end
      end
      true
    end

    def self.run_unalias(args)
      if args.empty?
        puts 'unalias: usage: unalias name [name ...]'
        return false
      end

      args.each do |name|
        if @aliases.key?(name)
          @aliases.delete(name)
        else
          puts "unalias: #{name}: not found"
        end
      end
      true
    end

    def self.expand_alias(line)
      return line if line.empty?

      # Extract the first word
      first_word = line.split(/\s/, 2).first
      return line unless first_word

      if @aliases.key?(first_word)
        rest = line[first_word.length..]
        "#{@aliases[first_word]}#{rest}"
      else
        line
      end
    end

    def self.clear_aliases
      @aliases.clear
    end

    def self.run_source(args)
      if args.empty?
        puts 'source: usage: source filename [arguments]'
        return false
      end

      file = args.first
      file = File.expand_path(file)

      unless File.exist?(file)
        puts "source: #{file}: No such file or directory"
        return false
      end

      unless @executor
        puts 'source: executor not configured'
        return false
      end

      # Save and set script name and positional params
      old_script_name = @script_name_getter&.call
      old_positional_params = @positional_params_getter&.call
      @script_name_setter&.call(file)
      @positional_params_setter&.call(args[1..] || [])

      return_code = catch(:return) do
        File.readlines(file, chomp: true).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          begin
            @executor.call(line)
          rescue => e
            puts "source: #{e.message}"
          end
        end
        nil
      end

      # Restore script name and positional params
      @script_name_setter&.call(old_script_name) if old_script_name
      @positional_params_setter&.call(old_positional_params) if old_positional_params

      return_code.nil? || return_code == 0
    end

    def self.run_shift(args)
      n = args.first&.to_i || 1

      return false if n < 0

      params = @positional_params_getter&.call || []

      if n > params.length
        puts 'shift: shift count out of range'
        return false
      end

      @positional_params_setter&.call(params.drop(n))
      true
    end

    def self.run_set(args)
      # set -- arg1 arg2 arg3  sets positional params
      # set (no args) could list variables, but for now just clear params
      if args.empty?
        @positional_params_setter&.call([])
      elsif args.first == '--'
        @positional_params_setter&.call(args[1..] || [])
      else
        @positional_params_setter&.call(args)
      end
      true
    end

    def self.run_return(args)
      code = args.first&.to_i || 0
      throw :return, code
    end

    def self.run_read(args)
      prompt = nil
      vars = []

      # Parse options
      i = 0
      while i < args.length
        if args[i] == '-p' && args[i + 1]
          prompt = args[i + 1]
          i += 2
        else
          vars << args[i]
          i += 1
        end
      end

      # Default variable is REPLY
      vars << 'REPLY' if vars.empty?

      # Display prompt if specified
      print prompt if prompt

      # Read line from stdin
      line = $stdin.gets
      return false unless line

      line = line.chomp
      words = line.split

      # Assign to variables
      vars.each_with_index do |var, idx|
        if idx == vars.length - 1
          # Last variable gets remaining words
          ENV[var] = (words[idx..] || []).join(' ')
        else
          ENV[var] = words[idx] || ''
        end
      end

      true
    end

    def self.run_exit(args)
      code = args.first&.to_i || 0
      throw :exit, code
    end

    def self.run_jobs(_args)
      jobs = JobManager.instance.active
      if jobs.empty?
        # No output when no jobs
      else
        jobs.each { |job| puts job }
      end
      true
    end

    def self.run_fg(args)
      job = find_job(args)
      return false unless job

      puts job.command

      # Bring to foreground
      Process.kill('CONT', -job.pgid) if job.stopped?

      # Give terminal control to the job's process group
      begin
        # Wait for the job
        _, status = Process.wait2(job.pid, Process::WUNTRACED)

        if status.stopped?
          job.status = :stopped
          puts "\n[#{job.id}]  Stopped                 #{job.command}"
        else
          job.status = :done
          JobManager.instance.remove(job.id)
        end
      rescue Errno::ECHILD
        job.status = :done
        JobManager.instance.remove(job.id)
      end

      true
    end

    def self.run_bg(args)
      job = find_job(args)
      return false unless job

      unless job.stopped?
        puts "bg: job #{job.id} is not stopped"
        return false
      end

      job.status = :running
      Process.kill('CONT', -job.pgid)
      puts "[#{job.id}] #{job.command} &"
      true
    end

    def self.find_job(args)
      manager = JobManager.instance

      if args.empty?
        job = manager.last
        unless job
          puts 'fg: no current job'
          return nil
        end
        job
      else
        # Parse %n or just n
        id_str = args.first.to_s.delete_prefix('%')
        id = id_str.to_i
        job = manager.get(id)
        unless job
          puts "fg: %#{id}: no such job"
          return nil
        end
        job
      end
    end
  end
end
