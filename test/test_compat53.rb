# frozen_string_literal: true

require_relative 'test_helper'

class TestCompat53 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_compat53_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # compat53 tests
  def test_compat53_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('compat53')
  end

  def test_compat53_can_be_enabled
    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')
  end

  def test_compat53_can_be_disabled
    execute('shopt -s compat53')
    execute('shopt -u compat53')
    assert_false Rubish::Builtins.shopt_enabled?('compat53')
  end

  def test_compat53_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat53')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['compat53'][0]
  end

  def test_compat53_in_compat_options
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat53'
  end

  # Test compat options are mutually exclusive
  def test_compat53_disables_compat52
    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')

    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')
    assert_false Rubish::Builtins.shopt_enabled?('compat52')
  end

  def test_compat52_disables_compat53
    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')

    execute('shopt -s compat52')
    assert Rubish::Builtins.shopt_enabled?('compat52')
    assert_false Rubish::Builtins.shopt_enabled?('compat53')
  end

  def test_compat53_disables_other_compat_options
    execute('shopt -s compat50')
    assert Rubish::Builtins.shopt_enabled?('compat50')

    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')
    assert_false Rubish::Builtins.shopt_enabled?('compat50')
  end

  # Test shopt output for compat53
  def test_shopt_print_shows_compat53
    output = capture_output do
      execute('shopt compat53')
    end
    assert_match(/compat53/, output)
    assert_match(/off/, output)

    execute('shopt -s compat53')

    output = capture_output do
      execute('shopt compat53')
    end
    assert_match(/compat53/, output)
    assert_match(/on/, output)
  end

  # Test shopt -q for compat53
  def test_shopt_q_compat53
    result = Rubish::Builtins.run('shopt', ['-q', 'compat53'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'compat53'])
    result = Rubish::Builtins.run('shopt', ['-q', 'compat53'])
    assert result
  end

  # Test toggle behavior
  def test_toggle_compat53
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('compat53')

    # Enable
    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')

    # Disable
    execute('shopt -u compat53')
    assert_false Rubish::Builtins.shopt_enabled?('compat53')

    # Re-enable
    execute('shopt -s compat53')
    assert Rubish::Builtins.shopt_enabled?('compat53')
  end

  # Test that the option is listed in shopt output
  def test_compat53_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/compat53/, output)
  end

  # Test all compat options are present
  def test_all_compat_options_exist
    expected = %w[compat10 compat31 compat32 compat40 compat41 compat42 compat43 compat44 compat50 compat51 compat52 compat53]
    expected.each do |opt|
      assert Rubish::Builtins::SHELL_OPTIONS.key?(opt), "Missing option: #{opt}"
      assert_includes Rubish::Builtins::COMPAT_OPTIONS, opt, "Missing from COMPAT_OPTIONS: #{opt}"
    end
  end
end
