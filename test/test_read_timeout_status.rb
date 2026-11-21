# frozen_string_literal: true

require_relative 'test_helper'

# read -t that times out returns 128 + SIGALRM, as bash does
class TestReadTimeoutStatus < Test::Unit::TestCase
  def test_timeout_status
    repl = Rubish::REPL.new
    repl.send(:execute, 'read -t 0.1 v_rt < /dev/zero')
    assert_equal 142, repl.instance_variable_get(:@last_status)
  end
end
