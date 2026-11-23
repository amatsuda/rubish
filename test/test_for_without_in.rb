# frozen_string_literal: true

require_relative 'test_helper'

# `for name; do ...; done` without `in` iterates over the positional
# parameters, as in bash
class TestForWithoutIn < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_loops_over_the_positional_parameters
    out = capture_stdout { execute('set -- p q; for x; do echo "pos:$x"; done') }
    assert_equal "pos:p\npos:q\n", out
  end

  def test_loops_over_the_function_arguments
    out = capture_stdout { execute('f() { for a; do echo "<$a>"; done; }; f 1 "2 3"') }
    assert_equal "<1>\n<2 3>\n", out
  end

  def test_no_parameters_means_no_iteration
    out = capture_stdout { execute('set --; for x; do echo never; done; echo done') }
    assert_equal "done\n", out
  end
end
