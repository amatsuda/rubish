# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w[cd exit jobs fg bg export pwd].freeze

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
