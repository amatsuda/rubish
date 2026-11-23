# frozen_string_literal: true

require_relative 'test_helper'

# `${!name<op>...}`: expand indirectly through name, then apply the operator
# to the result, as bash does
class TestIndirectWithOperator < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_default_value_operator
    out = capture_stdout { execute('n=name; name=val; echo "${!n:-def}"; unset name; echo "${!n:-def}"') }
    assert_equal "val\ndef\n", out
  end

  def test_pattern_operators
    out = capture_stdout { execute('n=name; name=value; echo "${!n#va}" "${!n%ue}" "${!n/l/L}" "${!n^}"') }
    assert_equal "lue val vaLue Value\n", out
  end

  def test_substring_operator
    out = capture_stdout { execute('n=name; name=abcdef; echo "${!n:2:3}"') }
    assert_equal "cde\n", out
  end
end
