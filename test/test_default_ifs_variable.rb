# frozen_string_literal: true

require_relative 'test_helper'

# IFS is a set shell variable from the start, holding space, tab, newline
class TestDefaultIfsVariable < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_ifs_has_the_default_value
    out = capture_stdout { execute(%q{x=" "$'\t\n'; [[ "$IFS" == "$x" ]]; echo $?}) }
    assert_equal "0\n", out
  end

  def test_ifs_is_set
    out = capture_stdout { execute('[[ -v IFS ]]; echo $?; echo "${#IFS}"') }
    assert_equal "0\n3\n", out
  end
end
