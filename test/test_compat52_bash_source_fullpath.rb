# frozen_string_literal: true

require_relative 'test_helper'

class TestCompat52BashSourceFullpath < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_compat52_bash_source_fullpath_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # compat52 tests
  def test_compat52_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('compat52')
  end

  def test_compat52_can_be_enabled
    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')
  end

  def test_compat52_can_be_disabled
    execute('shopt -s compat52')
    execute('shopt -u compat52')
    assert_false Rubish::Builtins.shopt_enabled?('compat52')
  end

  def test_compat52_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat52')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['compat52'][0]
  end

  def test_compat52_in_compat_options
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat52'
  end

  # Test compat options are mutually exclusive
  def test_compat52_disables_compat51
    execute('shopt -s compat51')
    assert Rubish::Builtins.shopt_enabled?('compat51')

    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')
    assert_false Rubish::Builtins.shopt_enabled?('compat51')
  end

  def test_compat51_disables_compat52
    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')

    execute('shopt -s compat51')
    assert Rubish::Builtins.shopt_enabled?('compat51')
    assert_false Rubish::Builtins.shopt_enabled?('compat52')
  end

  # Test shopt output for compat52
  def test_shopt_print_shows_compat52
    output = capture_output do
      execute('shopt compat52')
    end
    assert_match(/compat52/, output)
    assert_match(/off/, output)

    execute('shopt -s compat52')

    output = capture_output do
      execute('shopt compat52')
    end
    assert_match(/compat52/, output)
    assert_match(/on/, output)
  end

  # Test shopt -q for compat52
  def test_shopt_q_compat52
    result = Rubish::Builtins.run('shopt', ['-q', 'compat52'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'compat52'])
    result = Rubish::Builtins.run('shopt', ['-q', 'compat52'])
    assert result
  end

  # Test toggle behavior
  def test_toggle_compat52
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('compat52')

    # Enable
    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')

    # Disable
    execute('shopt -u compat52')
    assert_false Rubish::Builtins.shopt_enabled?('compat52')

    # Re-enable
    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')
  end

  # Test that the option is listed in shopt output
  def test_compat52_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/compat52/, output)
  end

  # bash_source_fullpath tests
  def test_bash_source_fullpath_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('bash_source_fullpath')
  end

  def test_bash_source_fullpath_can_be_enabled
    execute('shopt -s bash_source_fullpath')
    assert Rubish::Builtins.shopt_enabled?('bash_source_fullpath')
  end

  def test_bash_source_fullpath_can_be_disabled
    execute('shopt -s bash_source_fullpath')
    execute('shopt -u bash_source_fullpath')
    assert_false Rubish::Builtins.shopt_enabled?('bash_source_fullpath')
  end

  def test_bash_source_fullpath_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('bash_source_fullpath')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['bash_source_fullpath'][0]
  end

  # Test shopt output for bash_source_fullpath
  def test_shopt_print_shows_bash_source_fullpath
    output = capture_output do
      execute('shopt bash_source_fullpath')
    end
    assert_match(/bash_source_fullpath/, output)
    assert_match(/off/, output)

    execute('shopt -s bash_source_fullpath')

    output = capture_output do
      execute('shopt bash_source_fullpath')
    end
    assert_match(/bash_source_fullpath/, output)
    assert_match(/on/, output)
  end

  # Test shopt -q for bash_source_fullpath
  def test_shopt_q_bash_source_fullpath
    result = Rubish::Builtins.run('shopt', ['-q', 'bash_source_fullpath'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'bash_source_fullpath'])
    result = Rubish::Builtins.run('shopt', ['-q', 'bash_source_fullpath'])
    assert result
  end

  # Test toggle behavior
  def test_toggle_bash_source_fullpath
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('bash_source_fullpath')

    # Enable
    execute('shopt -s bash_source_fullpath')
    assert Rubish::Builtins.shopt_enabled?('bash_source_fullpath')

    # Disable
    execute('shopt -u bash_source_fullpath')
    assert_false Rubish::Builtins.shopt_enabled?('bash_source_fullpath')

    # Re-enable
    execute('shopt -s bash_source_fullpath')
    assert Rubish::Builtins.shopt_enabled?('bash_source_fullpath')
  end

  # Test that the option is listed in shopt output
  def test_bash_source_fullpath_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/bash_source_fullpath/, output)
  end
end
