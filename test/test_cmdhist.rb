# frozen_string_literal: true

require_relative 'test_helper'

class TestCmdhist < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test cmdhist is enabled by default
  def test_cmdhist_enabled_by_default
    assert Rubish::Builtins.shopt_enabled?('cmdhist')
  end

  # Test lithist is disabled by default
  def test_lithist_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('lithist')
  end

  # Test incomplete_command_error? detects if statement
  def test_incomplete_command_error_if
    assert @repl.send(:incomplete_command_error?, 'Expected "fi" to close if statement')
  end

  # Test incomplete_command_error? detects while loop
  def test_incomplete_command_error_while
    assert @repl.send(:incomplete_command_error?, 'Expected "done" to close while loop')
  end

  # Test incomplete_command_error? detects until loop
  def test_incomplete_command_error_until
    assert @repl.send(:incomplete_command_error?, 'Expected "done" to close until loop')
  end

  # Test incomplete_command_error? detects for loop
  def test_incomplete_command_error_for
    assert @repl.send(:incomplete_command_error?, 'Expected "done" to close for loop')
  end

  # Test incomplete_command_error? detects select loop
  def test_incomplete_command_error_select
    assert @repl.send(:incomplete_command_error?, 'Expected "done" to close select loop')
  end

  # Test incomplete_command_error? detects case statement
  def test_incomplete_command_error_case
    assert @repl.send(:incomplete_command_error?, 'Expected "esac" to close case statement')
  end

  # Test incomplete_command_error? detects function body
  def test_incomplete_command_error_function
    assert @repl.send(:incomplete_command_error?, 'Expected "}" to close function body')
  end

  # Test incomplete_command_error? detects then keyword
  def test_incomplete_command_error_then
    assert @repl.send(:incomplete_command_error?, 'Expected "then" after if condition')
  end

  # Test incomplete_command_error? detects do keyword
  def test_incomplete_command_error_do
    assert @repl.send(:incomplete_command_error?, 'Expected "do" after while condition')
  end

  # Test incomplete_command_error? detects in keyword
  def test_incomplete_command_error_in
    assert @repl.send(:incomplete_command_error?, 'Expected "in" after for variable')
  end

  # Test non-incomplete errors are not detected
  def test_not_incomplete_for_unknown_error
    refute @repl.send(:incomplete_command_error?, 'Unknown error')
    refute @repl.send(:incomplete_command_error?, 'Syntax error near unexpected token')
    refute @repl.send(:incomplete_command_error?, 'command not found')
  end

  # Test continuation_prompt uses PS2
  def test_continuation_prompt_default
    ENV.delete('PS2')
    assert_equal '> ', @repl.send(:continuation_prompt)
  end

  def test_continuation_prompt_custom
    ENV['PS2'] = 'more> '
    assert_equal 'more> ', @repl.send(:continuation_prompt)
  end
end
