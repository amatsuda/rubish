# frozen_string_literal: true

module Rubish
  class Job
    attr_reader :id, :pid, :pgid, :command
    attr_accessor :status

    def initialize(id:, pid:, pgid:, command:)
      @id = id
      @pid = pid
      @pgid = pgid
      @command = command
      @status = :running
    end

    def running?
      @status == :running
    end

    def stopped?
      @status == :stopped
    end

    def done?
      @status == :done
    end

    def status_string
      case @status
      when :running then 'Running'
      when :stopped then 'Stopped'
      when :done then 'Done'
      else @status.to_s
      end
    end

    def to_s
      "[#{@id}] #{status_string.ljust(10)} #{@command}"
    end
  end

  class JobManager
    include Singleton

    def initialize
      @jobs = {}
      @next_id = 1
      @mutex = Mutex.new
    end

    def add(pid:, pgid:, command:)
      @mutex.synchronize do
        id = @next_id
        @next_id += 1
        job = Job.new(id: id, pid: pid, pgid: pgid, command: command)
        @jobs[id] = job
        job
      end
    end

    def remove(id)
      @mutex.synchronize { @jobs.delete(id) }
    end

    def get(id)
      @mutex.synchronize { @jobs[id] }
    end

    def all
      @mutex.synchronize { @jobs.values.dup }
    end

    def active
      @mutex.synchronize { @jobs.values.reject(&:done?) }
    end

    def last
      @mutex.synchronize { @jobs.values.last }
    end

    def find_by_pid(pid)
      @mutex.synchronize { @jobs.values.find { |j| j.pid == pid } }
    end

    def update_status(pid, status)
      job = find_by_pid(pid)
      return unless job

      if status.stopped?
        job.status = :stopped
      elsif status.exited? || status.signaled?
        job.status = :done
      end
      job
    end

    def check_background_jobs
      # Non-blocking wait for any child
      loop do
        pid, status = Process.wait2(-1, Process::WNOHANG | Process::WUNTRACED)
        break unless pid

        job = update_status(pid, status)
        if job&.done?
          puts "[#{job.id}]  Done                    #{job.command}"
          remove(job.id)
        elsif job&.stopped?
          puts "[#{job.id}]  Stopped                 #{job.command}"
        end
      end
    rescue Errno::ECHILD
      # No children, ignore
    end

    def clear
      @mutex.synchronize do
        @jobs.clear
        @next_id = 1
      end
    end
  end
end
