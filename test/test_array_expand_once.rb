# frozen_string_literal: true

require_relative 'test_helper'

class TestArrayExpandOnce < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_array_expand_once_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
    @original_env = {}
    %w[idx key arr].each do |var|
      @original_env[var] = ENV[var]
    end
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    @original_env.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # array_expand_once is disabled by default
  def test_array_expand_once_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('array_expand_once')
  end

  def test_array_expand_once_can_be_enabled
    execute('shopt -s array_expand_once')
    assert Rubish::Builtins.shopt_enabled?('array_expand_once')
  end

  def test_array_expand_once_can_be_disabled
    execute('shopt -s array_expand_once')
    execute('shopt -u array_expand_once')
    assert_false Rubish::Builtins.shopt_enabled?('array_expand_once')
  end

  # Test the option is in SHELL_OPTIONS
  def test_array_expand_once_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('array_expand_once')
    # SHELL_OPTIONS stores [default_value, description] arrays
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['array_expand_once'][0] # default off
  end

  # Test toggle behavior
  def test_toggle_array_expand_once
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('array_expand_once')

    # Enable
    execute('shopt -s array_expand_once')
    assert Rubish::Builtins.shopt_enabled?('array_expand_once')

    # Disable
    execute('shopt -u array_expand_once')
    assert_false Rubish::Builtins.shopt_enabled?('array_expand_once')

    # Re-enable
    execute('shopt -s array_expand_once')
    assert Rubish::Builtins.shopt_enabled?('array_expand_once')
  end

  # Test shopt output
  def test_shopt_print_shows_option
    output = capture_output do
      execute('shopt array_expand_once')
    end
    assert_match(/array_expand_once/, output)
    assert_match(/off/, output)

    execute('shopt -s array_expand_once')

    output = capture_output do
      execute('shopt array_expand_once')
    end
    assert_match(/array_expand_once/, output)
    assert_match(/on/, output)
  end

  # Test that the option is listed in shopt output
  def test_option_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/array_expand_once/, output)
  end

  # Test shopt -q for array_expand_once
  def test_shopt_q_array_expand_once
    # Default is disabled, so -q should return false
    result = Rubish::Builtins.run('shopt', ['-q', 'array_expand_once'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'array_expand_once'])
    result = Rubish::Builtins.run('shopt', ['-q', 'array_expand_once'])
    assert result
  end

  # Test that assoc_expand_once still works (backward compatibility)
  def test_assoc_expand_once_still_works
    assert_false Rubish::Builtins.shopt_enabled?('assoc_expand_once')
    execute('shopt -s assoc_expand_once')
    assert Rubish::Builtins.shopt_enabled?('assoc_expand_once')
  end

  # compat50 tests
  def test_compat50_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('compat50')
  end

  def test_compat50_can_be_enabled
    execute('shopt -s compat50')
    assert Rubish::Builtins.shopt_enabled?('compat50')
  end

  def test_compat50_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat50')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['compat50'][0]
  end

  def test_compat50_in_compat_options
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat50'
  end

  # compat51 tests
  def test_compat51_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('compat51')
  end

  def test_compat51_can_be_enabled
    execute('shopt -s compat51')
    assert Rubish::Builtins.shopt_enabled?('compat51')
  end

  def test_compat51_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat51')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['compat51'][0]
  end

  def test_compat51_in_compat_options
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat51'
  end

  # Test compat options are mutually exclusive
  def test_compat_options_mutually_exclusive
    execute('shopt -s compat50')
    assert Rubish::Builtins.shopt_enabled?('compat50')

    execute('shopt -s compat51')
    assert Rubish::Builtins.shopt_enabled?('compat51')
    assert_false Rubish::Builtins.shopt_enabled?('compat50')
  end

  # Test shopt output for compat options
  def test_shopt_print_shows_compat50
    output = capture_output do
      execute('shopt compat50')
    end
    assert_match(/compat50/, output)
  end

  def test_shopt_print_shows_compat51
    output = capture_output do
      execute('shopt compat51')
    end
    assert_match(/compat51/, output)
  end
end
