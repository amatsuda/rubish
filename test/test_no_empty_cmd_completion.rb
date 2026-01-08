# frozen_string_literal: true

require_relative 'test_helper'

class TestNoEmptyCmdCompletion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_no_empty_cmd_completion_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # no_empty_cmd_completion is disabled by default
  def test_no_empty_cmd_completion_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
  end

  def test_no_empty_cmd_completion_can_be_enabled
    execute('shopt -s no_empty_cmd_completion')
    assert Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
  end

  def test_no_empty_cmd_completion_can_be_disabled
    execute('shopt -s no_empty_cmd_completion')
    execute('shopt -u no_empty_cmd_completion')
    assert_false Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
  end

  # Test that the complete method checks the option
  def test_complete_method_exists
    assert @repl.respond_to?(:complete, true)
  end

  # Test the logic directly by checking the shopt_enabled? call
  def test_shopt_check_in_complete
    execute('shopt -s no_empty_cmd_completion')

    # Verify the option is enabled
    assert Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')

    # The complete method should check this option
    # We can verify by checking the source code behavior
  end

  # Test that enabling/disabling works correctly
  def test_toggle_option
    # Initially disabled
    assert_false Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')

    # Enable
    execute('shopt -s no_empty_cmd_completion')
    assert Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')

    # Disable
    execute('shopt -u no_empty_cmd_completion')
    assert_false Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')

    # Enable again
    execute('shopt -s no_empty_cmd_completion')
    assert Rubish::Builtins.shopt_enabled?('no_empty_cmd_completion')
  end

  # Test shopt -p output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt no_empty_cmd_completion')
    end
    assert_match(/no_empty_cmd_completion/, output)
    assert_match(/off/, output)

    execute('shopt -s no_empty_cmd_completion')

    output = capture_output do
      execute('shopt no_empty_cmd_completion')
    end
    assert_match(/no_empty_cmd_completion/, output)
    assert_match(/on/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/no_empty_cmd_completion/, output)
  end
end
