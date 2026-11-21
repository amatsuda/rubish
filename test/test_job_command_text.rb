# frozen_string_literal: true

require_relative 'test_helper'

# A background job remembers the command line it was started with, so
# `jobs` can show it
class TestJobCommandText < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    Rubish::JobManager.instance.clear
    Rubish::Builtins.enable_interactive_mode
  end

  def teardown
    Rubish::JobManager.instance.all.each { |j| Process.kill('KILL', j.pid) rescue nil }
    Rubish::JobManager.instance.clear
  end

  def test_job_records_the_command_line
    capture_stdout { execute('sleep 5 &') }
    job = Rubish::JobManager.instance.all.last
    assert_equal 'sleep 5 &', job.command
    out = capture_stdout { execute('jobs') }
    assert_match(/sleep 5 &/, out)
  end
end
