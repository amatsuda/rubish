# frozen_string_literal: true

module Rubish
  class Job
    attr_reader :id, :pid, :pgid, :command
    attr_accessor :status, :termsig

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

    # What strsignal gives for the common ones; bash prints these for a job
    # that a signal ended, followed by the signal number
    SIGNAL_DESCRIPTIONS = {
      'HUP' => 'Hangup', 'INT' => 'Interrupt', 'QUIT' => 'Quit', 'ABRT' => 'Abort trap',
      'KILL' => 'Killed', 'SEGV' => 'Segmentation fault', 'PIPE' => 'Broken pipe',
      'ALRM' => 'Alarm clock', 'TERM' => 'Terminated', 'USR1' => 'User defined signal 1',
      'USR2' => 'User defined signal 2'
    }.freeze

    def status_string
      case @status
      when :running then 'Running'
      when :stopped then 'Stopped'
      when :done
        return 'Done' unless @termsig

        name = Signal.signame(@termsig) || @termsig.to_s
        "#{SIGNAL_DESCRIPTIONS.fetch(name, "Signal #{name}")}: #{@termsig}"
      else @status.to_s
      end
    end

    # bash's layout: `[1]+  Running                 sleep 1 &`, with + for the
    # current job and - for the previous one
    def to_s
      format('[%d]%s  %-24s%s', @id, JobManager.instance.marker(self), status_string, @command)
    end
  end

  # Job bookkeeping for the shell. Everything here runs on the main thread,
  # including the SIGCHLD trap installed for `set -b`, and Ruby forbids
  # taking a Mutex from a trap handler, so this class deliberately has no
  # lock and does not use Singleton (whose #instance locks too).
  class JobManager
    def self.instance
      @instance ||= new
    end

    def initialize
      @jobs = {}
      @next_id = 1
    end

    def add(pid:, pgid:, command:)
      # Numbers start over once the table is empty (bash)
      id = (@jobs.keys.max || 0) + 1
      job = Job.new(id: id, pid: pid, pgid: pgid, command: command)
      @jobs[id] = job
      job
    end

    def remove(id)
      @jobs.delete(id)
    end

    def get(id)
      @jobs[id]
    end

    def all
      @jobs.values.dup
    end

    def active
      @jobs.values.reject(&:done?)
    end

    def last
      @jobs.values.last
    end

    def find_by_pid(pid)
      @jobs.values.find { |j| j.pid == pid }
    end

    def update_status(pid, status)
      job = find_by_pid(pid)
      return unless job

      if status.stopped?
        job.status = :stopped
      elsif status.exited? || status.signaled?
        job.status = :done
        job.termsig = status.termsig if status.signaled?
      end
      job
    end

    # `+` for the most recent job, `-` for the one before it, as bash marks
    # the current and previous jobs
    def marker(job)
      recent = @jobs.values.last(2).reverse
      case recent.index(job)
      when 0 then '+'
      when 1 then '-'
      else ' '
      end
    end

    def check_background_jobs
      # Non-blocking wait for any child
      loop do
        pid, status = Process.wait2(-1, Process::WNOHANG | Process::WUNTRACED)
        break unless pid

        job = update_status(pid, status)
        if job&.done?
          puts job
          remove(job.id)
        elsif job&.stopped?
          puts job
        end
      end
    rescue Errno::ECHILD
      # No children, ignore
    end

    def clear
      @jobs.clear
      @next_id = 1
    end

    # Wait until the number of active jobs is below CHILD_MAX
    # Returns true if we can proceed, false if CHILD_MAX is not set or unlimited
    def wait_for_child_slot
      child_max = child_max_limit
      return true unless child_max

      while active_count >= child_max
        # Wait for any child to change state
        begin
          pid, status = Process.wait2(-1, Process::WUNTRACED)
          update_status(pid, status) if pid
        rescue Errno::ECHILD
          # No more children, we can proceed
          break
        end
      end
      true
    end

    def active_count
      @jobs.values.count { |j| j.running? || j.stopped? }
    end

    def child_max_limit
      val = ENV['CHILD_MAX']
      return nil unless val && !val.empty?

      limit = val.to_i
      limit > 0 ? limit : nil
    end
  end
end
