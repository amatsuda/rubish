# frozen_string_literal: true

require_relative 'test_helper'

# unalias -a removes every alias
class TestUnaliasAll < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved = Rubish::Builtins.current_state.aliases.dup
  end

  def teardown
    Rubish::Builtins.current_state.aliases.replace(@saved)
  end

  def test_removes_all_aliases
    execute("alias ua_one='echo one'; alias ua_two='echo two'")
    execute('unalias -a')
    out = capture_stdout { execute('alias') }
    assert_equal '', out
    assert_equal 0, @repl.instance_variable_get(:@last_status)
  end
end
