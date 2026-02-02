# frozen_string_literal: true

module Rubish
  # Background lazy loader for slow shell initializations
  #
  # Usage in config:
  #   lazy_load {
  #     `rbenv init - --no-rehash bash`
  #   }
  #
  # The block runs in a background thread immediately.
  # Its return value (a string of shell code) is eval'd in the main thread
  # before the next prompt.
  #
  # Benefits:
  # - Shell starts instantly
  # - Slow inits run in parallel during startup
  # - By the time you need the command, it's usually ready
  #
  module LazyLoader
    @pending_tasks = []
    @completed_results = Queue.new
    @mutex = Mutex.new

    class << self
      # Register a lazy load task to run in background
      def register(name, executor, &block)
        task = {
          name: name,
          thread: nil,
          executor: executor,
          started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
        }

        task[:thread] = Thread.new do
          begin
            # Run the block and capture its return value (shell code to eval)
            result = block.call
            # If result is a string, it's shell code to eval
            if result.is_a?(String) && !result.strip.empty?
              @completed_results << {name: name, code: result, error: nil, started_at: task[:started_at]}
            else
              @completed_results << {name: name, code: nil, error: nil, started_at: task[:started_at]}
            end
          rescue => e
            @completed_results << {name: name, code: nil, error: e, started_at: task[:started_at]}
          end
        end

        @mutex.synchronize { @pending_tasks << task }
      end

      # Check for completed background tasks and apply their results
      # Called before each prompt
      def apply_completed(executor)
        applied = []

        while !@completed_results.empty?
          begin
            item = @completed_results.pop(true) # non-blocking
          rescue ThreadError
            break
          end

          if item[:error]
            $stderr.puts "lazy_load: #{item[:error].message}"
          elsif item[:code]
            begin
              # Execute the shell code in main thread
              executor.call(item[:code])
              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - item[:started_at]
              applied << {name: item[:name], elapsed: elapsed}
            rescue => e
              $stderr.puts "lazy_load: #{e.message}"
            end
          end
        end

        # Report if profiling is enabled
        if defined?(StartupProfiler) && StartupProfiler.enabled && applied.any?
          applied.each do |info|
            puts "  [lazy] #{info[:name]}: loaded in background (#{(info[:elapsed] * 1000).round(1)}ms)"
          end
        end

        applied.map { |a| a[:name] }
      end

      # Wait for all pending tasks to complete (useful for scripts)
      def wait_all(executor, timeout: 30)
        deadline = Time.now + timeout

        @mutex.synchronize { @pending_tasks.dup }.each do |task|
          remaining = deadline - Time.now
          break if remaining <= 0
          task[:thread]&.join(remaining)
        end

        apply_completed(executor)
      end

      # Check if any tasks are still running
      def pending?
        @mutex.synchronize { @pending_tasks.any? { |t| t[:thread]&.alive? } }
      end

      # Get status of all tasks
      def status
        @mutex.synchronize do
          @pending_tasks.map do |task|
            {
              name: task[:name],
              running: task[:thread]&.alive?,
              elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - task[:started_at]
            }
          end
        end
      end

      # Clear all tasks (for testing)
      def clear!
        @mutex.synchronize { @pending_tasks.clear }
        @completed_results.clear rescue nil
      end
    end
  end
end
