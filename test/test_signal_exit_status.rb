# frozen_string_literal: true

require_relative 'test_helper'

# A command killed by a signal reports 128+signal in $? and PIPESTATUS
class TestSignalExitStatus < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  def test_signalled_command_status_is_128_plus_signal
    capture_output { execute('sh -c "kill -TERM \\$\\$"') }
    assert_equal 128 + Signal.list['TERM'], last_status
  end

  def test_pipestatus_reports_sigpipe_for_head_closing_the_pipe
    Dir.mktmpdir('rubish_sigpipe') do |dir|
      out = File.join(dir, 'out.txt')
      execute("yes | head -1 > #{out}; echo \"${PIPESTATUS[0]} ${PIPESTATUS[1]}\" > #{out}")
      assert_equal "#{128 + Signal.list['PIPE']} 0\n", File.read(out)
    end
  end

  def test_wait_on_killed_background_job
    capture_output { execute('sleep 5 & kill -TERM $!; wait $!') }
    assert_equal 128 + Signal.list['TERM'], last_status
  end

  def test_command_substitution_of_signalled_command
    capture_output { execute('x=$(sh -c "kill -KILL \\$\\$")') }
    assert_equal 128 + Signal.list['KILL'], last_status
  end
end
