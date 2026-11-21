# frozen_string_literal: true

require_relative 'test_helper'

# ${##}, ${#?}, ${#1}: the length of a special or positional parameter
class TestSpecialParamLength < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_lengths_in_generated_code
    @repl.positional_params = %w[abc de]
    out = capture_stdout { execute('false; echo "${##} ${#?} ${#1} ${#2}"; true') }
    assert_equal "1 1 3 2\n", out
  end

  def test_lengths_on_the_direct_builtin_path
    @repl.positional_params = %w[abcd]
    out = capture_stdout { execute('echo ${##} ${#1} ${#$}') }
    assert_equal "1 4 #{Process.pid.to_s.length}\n", out
  end
end
