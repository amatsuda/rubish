# frozen_string_literal: true

require_relative 'test_helper'

# Field splitting with a non-whitespace IFS: adjacent delimiters make empty
# fields, a trailing delimiter does not add one, mixed IFS keeps the
# empties between non-whitespace delimiters
class TestIfsFieldSplitting < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('unset IFS')
  end

  def test_trailing_delimiter_adds_no_field
    out = capture_stdout { execute('IFS=:; a=":x:"; set -- $a; echo $# "[$1]"') }
    assert_equal "2 []\n", out
  end

  def test_adjacent_delimiters_make_an_empty_field
    out = capture_stdout { execute('IFS=:; a="x::y"; set -- $a; echo $# "[$2]"') }
    assert_equal "3 []\n", out
  end

  def test_mixed_ifs_keeps_empty_fields_between_non_whitespace_delimiters
    out = capture_stdout { execute('IFS=": "; a="x::y"; set -- $a; echo $#; a="x : y"; set -- $a; echo $#') }
    assert_equal "3\n2\n", out
  end
end
