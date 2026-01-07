# frozen_string_literal: true

require_relative 'test_helper'

class TestHistverify < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_set_options = Rubish::Builtins.instance_variable_get(:@set_options).dup
    # Clear Reline history and pre_input_hook
    Reline::HISTORY.clear
    Reline.pre_input_hook = nil
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.instance_variable_set(:@set_options, @original_set_options)
    Reline::HISTORY.clear
    Reline.pre_input_hook = nil
  end

  def expand_history_only(line)
    @repl.send(:expand_history_only, line)
  end

  def test_histverify_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('histverify')
  end

  def test_histverify_can_be_enabled
    execute('shopt -s histverify')
    assert Rubish::Builtins.shopt_enabled?('histverify')
  end

  def test_histverify_can_be_disabled
    execute('shopt -s histverify')
    execute('shopt -u histverify')
    assert_false Rubish::Builtins.shopt_enabled?('histverify')
  end

  def test_expand_history_only_returns_expansion
    # Add a command to history
    Reline::HISTORY << 'echo hello'

    # Check that !! expands
    result, expanded = expand_history_only('!!')
    assert expanded
    assert_equal 'echo hello', result
  end

  def test_expand_history_only_no_expansion_when_no_history_chars
    result, expanded = expand_history_only('echo hello')
    assert_false expanded
    assert_equal 'echo hello', result
  end

  def test_expand_history_only_suppresses_output
    # Add a command to history
    Reline::HISTORY << 'echo test'

    # Capture stdout to verify nothing is printed
    original_stdout = $stdout
    $stdout = StringIO.new
    result, expanded = expand_history_only('!!')
    output = $stdout.string
    $stdout = original_stdout

    assert expanded
    assert_equal '', output  # No output during silent expansion
  end

  def test_expand_history_only_handles_errors_silently
    # Try to expand a non-existent history event
    original_stdout = $stdout
    $stdout = StringIO.new
    result, expanded = expand_history_only('!999')
    output = $stdout.string
    $stdout = original_stdout

    # Should not print error message
    assert_equal '', output
  end

  def test_expand_history_only_with_word_designator
    Reline::HISTORY << 'git commit -m "test"'

    result, expanded = expand_history_only('!!:0')
    assert expanded
    assert_equal 'git', result
  end

  def test_expand_history_only_with_last_arg
    Reline::HISTORY << 'echo one two three'

    result, expanded = expand_history_only('!$')
    assert expanded
    assert_equal 'three', result
  end

  def test_expand_history_only_with_quick_substitution
    Reline::HISTORY << 'echo hello'

    result, expanded = expand_history_only('^hello^world^')
    assert expanded
    assert_equal 'echo world', result
  end

  def test_histverify_without_history_expansion_executes_normally
    execute('shopt -s histverify')

    # Command without history expansion should execute
    output = capture_stdout { execute('echo test') }
    assert_match(/test/, output)
  end
end
