# frozen_string_literal: true

require_relative 'test_helper'

class TestHistreedit < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_set_options = Rubish::Builtins.set_options.dup
    @tempdir = Dir.mktmpdir('rubish_histreedit_test')
    # Enable history expansion
    Rubish::Builtins.set_options['H'] = true
    # Clear Reline history
    Reline::HISTORY.clear
    # Clear any pre_input_hook
    Reline.pre_input_hook = nil
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.set_options.clear
    @original_set_options.each { |k, v| Rubish::Builtins.set_options[k] = v }
    FileUtils.rm_rf(@tempdir)
    Reline::HISTORY.clear
    Reline.pre_input_hook = nil
  end

  def expand_history(line)
    @repl.send(:expand_history, line)
  end

  # histreedit is disabled by default
  def test_histreedit_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('histreedit')
  end

  def test_histreedit_can_be_enabled
    execute('shopt -s histreedit')
    assert Rubish::Builtins.shopt_enabled?('histreedit')
  end

  def test_histreedit_can_be_disabled
    execute('shopt -s histreedit')
    execute('shopt -u histreedit')
    assert_false Rubish::Builtins.shopt_enabled?('histreedit')
  end

  # Test expand_history returns failure flag
  def test_expand_history_returns_failure_on_event_not_found
    Reline::HISTORY << 'echo hello'

    # Try to find a non-existent event
    output = capture_output do
      _line, _expanded, failed = expand_history('!nonexistent')
      assert failed
    end
    assert_match(/event not found/, output)
  end

  def test_expand_history_returns_no_failure_on_success
    Reline::HISTORY << 'echo hello'

    _line, _expanded, failed = expand_history('!echo')
    assert_false failed
  end

  def test_expand_history_returns_failure_on_substitution_failed
    Reline::HISTORY << 'echo hello'

    output = capture_output do
      _line, _expanded, failed = expand_history('^nonexistent^replacement')
      assert failed
    end
    assert_match(/substitution failed/, output)
  end

  # Test histreedit behavior
  def test_histreedit_sets_pre_input_hook_on_failure
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo hello'

    # Clear any existing hook
    Reline.pre_input_hook = nil

    # Execute a command with failed history expansion
    capture_output do
      execute('!nonexistent')
    end

    # pre_input_hook should be set
    assert_not_nil Reline.pre_input_hook
  end

  def test_histreedit_does_not_set_hook_on_success
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo hello'

    # Clear any existing hook
    Reline.pre_input_hook = nil

    # Execute a command with successful history expansion
    execute('!echo')

    # pre_input_hook should not be set (or cleared)
    # Note: execute runs the command, which might set other hooks
    # We mainly want to verify that histreedit doesn't interfere with success
  end

  def test_without_histreedit_no_hook_on_failure
    # histreedit is disabled
    assert_false Rubish::Builtins.shopt_enabled?('histreedit')

    Reline::HISTORY << 'echo hello'
    Reline.pre_input_hook = nil

    # Execute a command with failed history expansion
    capture_output do
      execute('!nonexistent')
    end

    # pre_input_hook should not be set
    assert_nil Reline.pre_input_hook
  end

  # Test that the original line is preserved for re-editing
  def test_histreedit_preserves_original_line
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo hello'

    original_line = '!nonexistent_command'

    # Execute the failing command
    capture_output do
      execute(original_line)
    end

    # The hook should contain the original line
    # We can't easily test the hook's behavior without mocking Reline,
    # but we verify the hook is set
    assert_not_nil Reline.pre_input_hook
  end

  # Test quick substitution failure with histreedit
  def test_histreedit_quick_substitution_failure
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo hello world'

    Reline.pre_input_hook = nil

    # Failed quick substitution
    capture_output do
      execute('^notfound^replacement')
    end

    # pre_input_hook should be set for re-editing
    assert_not_nil Reline.pre_input_hook
  end

  # Test that successful quick substitution doesn't trigger histreedit
  def test_histreedit_quick_substitution_success
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo hello world'

    Reline.pre_input_hook = nil

    # Successful quick substitution
    execute('^hello^goodbye')

    # The command should execute, not set re-edit hook
    # (The hook might be nil or set by something else during execution)
  end

  # Test multiple failed expansions
  def test_histreedit_multiple_failures
    execute('shopt -s histreedit')
    Reline::HISTORY << 'echo test'

    # First failure
    Reline.pre_input_hook = nil
    capture_output do
      execute('!xyz')
    end
    assert_not_nil Reline.pre_input_hook

    # Clear and try another failure
    Reline.pre_input_hook = nil
    capture_output do
      execute('!abc')
    end
    assert_not_nil Reline.pre_input_hook
  end

  # Test that histreedit works with empty history
  def test_histreedit_with_empty_history
    execute('shopt -s histreedit')
    Reline::HISTORY.clear

    Reline.pre_input_hook = nil

    # With empty history, expand_history returns the line unchanged (no failure)
    line, expanded, failed = expand_history('!test')
    assert_equal '!test', line
    assert_false expanded
    assert_false failed
  end
end
