# frozen_string_literal: true

require_relative 'test_helper'

# In [[ ]], a quoted right-hand side of == and != is matched literally
class TestConditionalQuotedPattern < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def status(line)
    execute(line)
    @repl.instance_variable_get(:@last_status)
  end

  def test_quoted_pattern_is_literal
    assert_equal 1, status('[[ abc == "a*c" ]]')
    assert_equal 0, status('[[ "a*c" == "a*c" ]]')
    assert_equal 0, status('[[ abc != "a*c" ]]')
  end

  def test_unquoted_pattern_still_matches
    assert_equal 0, status('[[ abc == a*c ]]')
    p = 'a?c'
    execute("pat_q=#{p}")
    assert_equal 0, status('[[ abc == $pat_q ]]')
    assert_equal 1, status('[[ abc == "$pat_q" ]]')
  end
end
