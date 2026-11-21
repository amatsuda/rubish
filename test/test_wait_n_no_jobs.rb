# frozen_string_literal: true

require_relative 'test_helper'

# `wait -n` with no child to wait for returns 127, as bash does
class TestWaitNNoJobs < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    Rubish::JobManager.instance.clear
  end

  def test_wait_n_without_jobs_returns_127
    execute('wait -n')
    assert_equal 127, @repl.instance_variable_get(:@last_status)
  end
end
