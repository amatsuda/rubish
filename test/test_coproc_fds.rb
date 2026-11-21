# frozen_string_literal: true

require_relative 'test_helper'

# The descriptors a coproc publishes in COPROC[0] / COPROC[1] can be used with
# >&N, <&N and read -u N
class TestCoprocFds < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_write_to_and_read_from_the_coprocess
    capture_stdout { execute('coproc { read x; echo "got $x"; }') }
    execute('echo hi >&"${COPROC[1]}"')
    execute('read -t 5 y <&"${COPROC[0]}"')
    assert_equal 'got hi', get_shell_var('y')
  end

  def test_read_u_from_the_coprocess
    capture_stdout { execute('coproc UP { tr a-z A-Z; }') }
    execute('echo abc >&"${UP[1]}"')
    execute('eval "exec ${UP[1]}>&-"')
    execute('read -t 5 -u "${UP[0]}" z')
    assert_equal 'ABC', get_shell_var('z')
  end
end
