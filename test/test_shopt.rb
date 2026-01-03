# frozen_string_literal: true

require_relative 'test_helper'

class TestShopt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_shopt_test')
    # Clear shell options between tests
    Rubish::Builtins.shell_options.clear
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test shopt is a builtin
  def test_shopt_is_builtin
    assert Rubish::Builtins.builtin?('shopt')
  end

  # Test shopt lists all options
  def test_shopt_lists_all
    output = capture_output { Rubish::Builtins.run('shopt', []) }
    assert_match(/autocd/, output)
    assert_match(/dotglob/, output)
    assert_match(/globstar/, output)
    assert_match(/nullglob/, output)
    lines = output.strip.split("\n")
    assert lines.length >= 20
  end

  # Test shopt -s enables option
  def test_shopt_s_enables
    result = Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    assert result
    assert Rubish::Builtins.shopt_enabled?('dotglob')
  end

  # Test shopt -u disables option
  def test_shopt_u_disables
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    result = Rubish::Builtins.run('shopt', ['-u', 'dotglob'])
    assert result
    assert_false Rubish::Builtins.shopt_enabled?('dotglob')
  end

  # Test shopt -p prints reusable format
  def test_shopt_p_reusable_format
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-p', 'dotglob']) }
    assert_equal "shopt -s dotglob\n", output
  end

  # Test shopt -p for disabled option
  def test_shopt_p_disabled
    output = capture_output { Rubish::Builtins.run('shopt', ['-p', 'dotglob']) }
    assert_equal "shopt -u dotglob\n", output
  end

  # Test shopt -q quiet mode
  def test_shopt_q_quiet
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-q', 'dotglob']) }
    assert_equal '', output
  end

  # Test shopt -q returns status
  def test_shopt_q_returns_status
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    result = Rubish::Builtins.run('shopt', ['-q', 'dotglob'])
    assert result

    Rubish::Builtins.run('shopt', ['-u', 'dotglob'])
    result = Rubish::Builtins.run('shopt', ['-q', 'dotglob'])
    assert_false result
  end

  # Test shopt with invalid option name
  def test_shopt_invalid_option_name
    output = capture_output do
      result = Rubish::Builtins.run('shopt', ['-s', 'nonexistent'])
      assert_false result
    end
    assert_match(/invalid shell option name/, output)
  end

  # Test shopt with invalid flag
  def test_shopt_invalid_flag
    output = capture_output do
      result = Rubish::Builtins.run('shopt', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test shopt -s and -u together fails
  def test_shopt_s_u_together_fails
    output = capture_output do
      result = Rubish::Builtins.run('shopt', ['-s', '-u', 'dotglob'])
      assert_false result
    end
    assert_match(/cannot set and unset/, output)
  end

  # Test shopt -s lists enabled options
  def test_shopt_s_lists_enabled
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    Rubish::Builtins.run('shopt', ['-s', 'globstar'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-s']) }
    assert_match(/dotglob/, output)
    assert_match(/globstar/, output)
    # cmdhist and expand_aliases are on by default
    assert_match(/cmdhist/, output)
  end

  # Test shopt -u lists disabled options
  def test_shopt_u_lists_disabled
    output = capture_output { Rubish::Builtins.run('shopt', ['-u']) }
    assert_match(/dotglob/, output)
    assert_match(/nullglob/, output)
  end

  # Test shopt multiple options
  def test_shopt_multiple_options
    result = Rubish::Builtins.run('shopt', ['-s', 'dotglob', 'globstar', 'nullglob'])
    assert result
    assert Rubish::Builtins.shopt_enabled?('dotglob')
    assert Rubish::Builtins.shopt_enabled?('globstar')
    assert Rubish::Builtins.shopt_enabled?('nullglob')
  end

  # Test shopt shows on/off
  def test_shopt_shows_on_off
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    output = capture_output { Rubish::Builtins.run('shopt', ['dotglob']) }
    assert_match(/on/, output)

    Rubish::Builtins.run('shopt', ['-u', 'dotglob'])
    output = capture_output { Rubish::Builtins.run('shopt', ['dotglob']) }
    assert_match(/off/, output)
  end

  # Test shopt_enabled? helper
  def test_shopt_enabled_helper
    # Default values
    assert Rubish::Builtins.shopt_enabled?('cmdhist')  # default on
    assert_false Rubish::Builtins.shopt_enabled?('dotglob')  # default off

    # After setting
    Rubish::Builtins.run('shopt', ['-s', 'dotglob'])
    assert Rubish::Builtins.shopt_enabled?('dotglob')
  end

  # Test login_shell is read-only
  def test_login_shell_readonly
    output = capture_output do
      result = Rubish::Builtins.run('shopt', ['-s', 'login_shell'])
      assert_false result
    end
    assert_match(/cannot set option/, output)
  end

  # Test type identifies shopt as builtin
  def test_type_identifies_shopt_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['shopt']) }
    assert_match(/shopt is a shell builtin/, output)
  end

  # Test shopt via REPL
  def test_shopt_via_repl
    execute('shopt -s dotglob')
    assert Rubish::Builtins.shopt_enabled?('dotglob')
  end
end
