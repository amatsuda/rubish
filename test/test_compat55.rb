# frozen_string_literal: true

require_relative 'test_helper'

class TestCompat55 < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @tempdir = Dir.mktmpdir('rubish_compat55_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    FileUtils.rm_rf(@tempdir)
  end

  # compat55 tests
  def test_compat55_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('compat55')
  end

  def test_compat55_can_be_enabled
    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')
  end

  def test_compat55_can_be_disabled
    execute('shopt -s compat55')
    execute('shopt -u compat55')
    assert_false Rubish::Builtins.shopt_enabled?('compat55')
  end

  def test_compat55_in_shell_options
    assert Rubish::Builtins::SHELL_OPTIONS.key?('compat55')
    assert_equal false, Rubish::Builtins::SHELL_OPTIONS['compat55'][0]
  end

  def test_compat55_in_compat_options
    assert_includes Rubish::Builtins::COMPAT_OPTIONS, 'compat55'
  end

  # Test compat options are mutually exclusive
  def test_compat55_disables_compat54
    execute('shopt -s compat54')
    assert Rubish::Builtins.shopt_enabled?('compat54')

    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')
    assert_false Rubish::Builtins.shopt_enabled?('compat54')
  end

  def test_compat54_disables_compat55
    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')

    execute('shopt -s compat54')
    assert Rubish::Builtins.shopt_enabled?('compat54')
    assert_false Rubish::Builtins.shopt_enabled?('compat55')
  end

  def test_compat55_disables_other_compat_options
    execute('shopt -s compat50')
    assert Rubish::Builtins.shopt_enabled?('compat50')

    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')
    assert_false Rubish::Builtins.shopt_enabled?('compat50')
  end

  # Test shopt output for compat55
  def test_shopt_print_shows_compat55
    output = capture_output do
      execute('shopt compat55')
    end
    assert_match(/compat55/, output)
    assert_match(/off/, output)

    execute('shopt -s compat55')

    output = capture_output do
      execute('shopt compat55')
    end
    assert_match(/compat55/, output)
    assert_match(/on/, output)
  end

  # Test shopt -q for compat55
  def test_shopt_q_compat55
    result = Rubish::Builtins.run('shopt', ['-q', 'compat55'])
    assert_false result

    Rubish::Builtins.run('shopt', ['-s', 'compat55'])
    result = Rubish::Builtins.run('shopt', ['-q', 'compat55'])
    assert result
  end

  # Test toggle behavior
  def test_toggle_compat55
    # Default: disabled
    assert_false Rubish::Builtins.shopt_enabled?('compat55')

    # Enable
    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')

    # Disable
    execute('shopt -u compat55')
    assert_false Rubish::Builtins.shopt_enabled?('compat55')

    # Re-enable
    execute('shopt -s compat55')
    assert Rubish::Builtins.shopt_enabled?('compat55')
  end

  # Test that the option is listed in shopt output
  def test_compat55_in_shopt_list
    output = capture_output do
      execute('shopt')
    end
    assert_match(/compat55/, output)
  end

  # Test all compat options are present including compat55
  def test_all_compat_options_exist
    expected = %w[compat10 compat31 compat32 compat40 compat41 compat42 compat43 compat44 compat50 compat51 compat52 compat53 compat54 compat55]
    expected.each do |opt|
      assert Rubish::Builtins::SHELL_OPTIONS.key?(opt), "Missing option: #{opt}"
      assert_includes Rubish::Builtins::COMPAT_OPTIONS, opt, "Missing from COMPAT_OPTIONS: #{opt}"
    end
  end
end
