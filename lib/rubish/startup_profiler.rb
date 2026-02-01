# frozen_string_literal: true

module Rubish
  # Startup profiler for measuring shell initialization time
  # Enable with RUBISH_PROF=1 or --prof flag
  #
  # Usage:
  #   RUBISH_PROF=1 rubish
  #   rubish --prof
  #
  # Output shows timing for each startup phase, sorted by duration.
  module StartupProfiler
    @enabled = false
    @entries = []
    @start_time = nil

    class << self
      attr_accessor :enabled

      def start!
        @enabled = true
        @entries = []
        @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def measure(name)
        return yield unless @enabled

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @entries << {name: name, time: elapsed}
        result
      end

      def report
        return unless @enabled
        return if @entries.empty?

        total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time

        # Sort by time descending
        sorted = @entries.sort_by { |e| -e[:time] }

        # Calculate column widths
        max_name_len = sorted.map { |e| e[:name].length }.max
        max_name_len = [max_name_len, 4].max  # minimum "name" header

        puts
        puts "\e[1mRubish startup profile:\e[0m"
        puts '-' * (max_name_len + 30)
        puts format("%-#{max_name_len}s  %10s  %7s", 'Phase', 'Time (ms)', '%')
        puts '-' * (max_name_len + 30)

        sorted.each do |entry|
          ms = entry[:time] * 1000
          pct = (entry[:time] / total_time * 100).round(1)
          puts format("%-#{max_name_len}s  %10.2f  %6.1f%%", entry[:name], ms, pct)
        end

        puts '-' * (max_name_len + 30)
        puts format("%-#{max_name_len}s  %10.2f  %6.1f%%", 'Total', total_time * 1000, 100.0)
        puts
      end
    end
  end
end
