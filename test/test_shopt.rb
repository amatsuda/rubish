# frozen_string_literal: true

require_relative 'test_helper'

class TestShopt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_shopt_test')
    # Clear shell options between tests
    Rubish::Builtins.current_state.shell_options.clear
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    # Reset set_options to defaults
    Rubish::Builtins.current_state.set_options.each_key do |k|
      # Reset to default values
      Rubish::Builtins.current_state.set_options[k] = case k
        when 'B', 'H', 'emacs', 'history' then true
        else false
      end
    end
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

  # globasciiranges tests

  def test_globasciiranges_is_valid_option
    output = capture_output { Rubish::Builtins.run('shopt', ['globasciiranges']) }
    assert_match(/globasciiranges/, output)
  end

  def test_globasciiranges_default_is_on
    # Ruby uses ASCII ordering by default, so globasciiranges defaults to on
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  def test_globasciiranges_can_be_disabled
    result = Rubish::Builtins.run('shopt', ['-u', 'globasciiranges'])
    assert result
    assert_false Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  def test_globasciiranges_can_be_enabled
    Rubish::Builtins.run('shopt', ['-u', 'globasciiranges'])
    result = Rubish::Builtins.run('shopt', ['-s', 'globasciiranges'])
    assert result
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  def test_globasciiranges_shows_in_list
    output = capture_output { Rubish::Builtins.run('shopt', []) }
    assert_match(/globasciiranges/, output)
  end

  def test_globasciiranges_print_format
    output = capture_output { Rubish::Builtins.run('shopt', ['-p', 'globasciiranges']) }
    assert_match(/shopt -s globasciiranges/, output)

    Rubish::Builtins.run('shopt', ['-u', 'globasciiranges'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-p', 'globasciiranges']) }
    assert_match(/shopt -u globasciiranges/, output)
  end

  def test_globasciiranges_via_repl
    execute('shopt -u globasciiranges')
    assert_false Rubish::Builtins.shopt_enabled?('globasciiranges')
    execute('shopt -s globasciiranges')
    assert Rubish::Builtins.shopt_enabled?('globasciiranges')
  end

  # shopt -o tests (for set -o options)

  def test_shopt_o_lists_set_options
    output = capture_output { Rubish::Builtins.run('shopt', ['-o']) }
    # POSIX-style set -o options
    assert_match(/errexit/, output)
    assert_match(/nounset/, output)
    assert_match(/xtrace/, output)
    assert_match(/noglob/, output)
    # Should NOT include shopt-only options (autocd is shopt-only)
    assert_no_match(/autocd/, output)
    assert_no_match(/cdspell/, output)
  end

  def test_shopt_so_enables_set_option
    result = Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    assert result
    assert Rubish::Builtins.set_option?('e')
  end

  def test_shopt_uo_disables_set_option
    Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    result = Rubish::Builtins.run('shopt', ['-uo', 'errexit'])
    assert result
    assert_false Rubish::Builtins.set_option?('e')
  end

  def test_shopt_o_specific_option
    output = capture_output { Rubish::Builtins.run('shopt', ['-o', 'errexit']) }
    assert_match(/errexit/, output)
    assert_match(/off/, output)
  end

  def test_shopt_o_enabled_option
    Rubish::Builtins.run('shopt', ['-so', 'xtrace'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-o', 'xtrace']) }
    assert_match(/xtrace/, output)
    assert_match(/on/, output)
  end

  def test_shopt_po_reusable_format
    Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-po', 'errexit']) }
    assert_equal "shopt -so errexit\n", output
  end

  def test_shopt_po_disabled_format
    output = capture_output { Rubish::Builtins.run('shopt', ['-po', 'errexit']) }
    assert_equal "shopt -uo errexit\n", output
  end

  def test_shopt_qo_quiet_mode
    Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-qo', 'errexit']) }
    assert_equal '', output
  end

  def test_shopt_qo_returns_status
    Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    result = Rubish::Builtins.run('shopt', ['-qo', 'errexit'])
    assert result

    Rubish::Builtins.run('shopt', ['-uo', 'errexit'])
    result = Rubish::Builtins.run('shopt', ['-qo', 'errexit'])
    assert_false result
  end

  def test_shopt_o_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('shopt', ['-so', 'autocd'])  # autocd is shopt-only
      assert_false result
    end
    assert_match(/invalid shell option name/, output)
  end

  def test_shopt_so_lists_enabled_set_options
    Rubish::Builtins.run('shopt', ['-so', 'errexit'])
    Rubish::Builtins.run('shopt', ['-so', 'xtrace'])
    output = capture_output { Rubish::Builtins.run('shopt', ['-so']) }
    assert_match(/errexit/, output)
    assert_match(/xtrace/, output)
    # braceexpand and histexpand are on by default
    assert_match(/braceexpand/, output)
  end

  def test_shopt_uo_lists_disabled_set_options
    output = capture_output { Rubish::Builtins.run('shopt', ['-uo']) }
    assert_match(/errexit/, output)
    assert_match(/nounset/, output)
  end

  def test_shopt_o_multiple_options
    result = Rubish::Builtins.run('shopt', ['-so', 'errexit', 'xtrace', 'nounset'])
    assert result
    assert Rubish::Builtins.set_option?('e')
    assert Rubish::Builtins.set_option?('x')
    assert Rubish::Builtins.set_option?('u')
  end

  def test_shopt_o_via_repl
    execute('shopt -so errexit')
    assert Rubish::Builtins.set_option?('e')
    execute('shopt -uo errexit')
    assert_false Rubish::Builtins.set_option?('e')
  end

  def test_shopt_o_noglob
    result = Rubish::Builtins.run('shopt', ['-so', 'noglob'])
    assert result
    assert Rubish::Builtins.set_option?('f')
  end

  def test_shopt_o_noclobber
    result = Rubish::Builtins.run('shopt', ['-so', 'noclobber'])
    assert result
    assert Rubish::Builtins.set_option?('C')
  end

  def test_shopt_help_mentions_o_option
    help = Rubish::Builtins::BUILTIN_HELP['shopt']
    assert_not_nil help
    assert help[:options].key?('-o')
  end
end
