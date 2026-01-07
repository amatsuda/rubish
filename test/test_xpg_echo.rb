# frozen_string_literal: true

require_relative 'test_helper'

class TestXpgEcho < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
  end

  def test_xpg_echo_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('xpg_echo')
  end

  def test_xpg_echo_can_be_enabled
    execute('shopt -s xpg_echo')
    assert Rubish::Builtins.shopt_enabled?('xpg_echo')
  end

  def test_xpg_echo_can_be_disabled
    execute('shopt -s xpg_echo')
    execute('shopt -u xpg_echo')
    assert_false Rubish::Builtins.shopt_enabled?('xpg_echo')
  end

  # Without xpg_echo, escapes are NOT expanded by default
  def test_echo_no_escape_expansion_by_default
    output = capture_stdout { execute('echo hello\\nworld') }
    assert_equal "hello\\nworld\n", output
  end

  # With xpg_echo, escapes ARE expanded by default
  def test_xpg_echo_expands_escapes_by_default
    execute('shopt -s xpg_echo')
    output = capture_stdout { execute('echo hello\\nworld') }
    assert_equal "hello\nworld\n", output
  end

  # -e flag enables escape expansion regardless of xpg_echo
  def test_echo_e_flag_enables_escapes
    output = capture_stdout { execute('echo -e hello\\nworld') }
    assert_equal "hello\nworld\n", output
  end

  # -E flag disables escape expansion regardless of xpg_echo
  def test_echo_E_flag_disables_escapes_with_xpg_echo
    execute('shopt -s xpg_echo')
    output = capture_stdout { execute('echo -E hello\\nworld') }
    assert_equal "hello\\nworld\n", output
  end

  # -n flag suppresses newline
  def test_echo_n_flag_suppresses_newline
    output = capture_stdout { execute('echo -n hello') }
    assert_equal 'hello', output
  end

  # Combined flags -ne
  def test_echo_combined_ne_flags
    output = capture_stdout { execute('echo -ne hello\\nworld') }
    assert_equal "hello\nworld", output
  end

  # Combined flags -en
  def test_echo_combined_en_flags
    output = capture_stdout { execute('echo -en hello\\tworld') }
    assert_equal "hello\tworld", output
  end

  # Test various escape sequences
  def test_echo_escape_newline
    output = capture_stdout { execute('echo -e a\\nb') }
    assert_equal "a\nb\n", output
  end

  def test_echo_escape_tab
    output = capture_stdout { execute('echo -e a\\tb') }
    assert_equal "a\tb\n", output
  end

  def test_echo_escape_carriage_return
    output = capture_stdout { execute('echo -e a\\rb') }
    assert_equal "a\rb\n", output
  end

  def test_echo_escape_backslash
    # Use single quotes to prevent shell from processing escapes
    # echo -e sees a\\b and outputs a\b (literal backslash)
    output = capture_stdout { execute("echo -e 'a\\\\b'") }
    assert_equal "a\\b\n", output
  end

  def test_echo_escape_alert
    output = capture_stdout { execute('echo -e a\\ab') }
    assert_equal "a\ab\n", output
  end

  def test_echo_escape_backspace
    output = capture_stdout { execute('echo -e a\\bb') }
    assert_equal "a\bb\n", output
  end

  def test_echo_escape_form_feed
    output = capture_stdout { execute('echo -e a\\fb') }
    assert_equal "a\fb\n", output
  end

  def test_echo_escape_vertical_tab
    output = capture_stdout { execute('echo -e a\\vb') }
    assert_equal "a\vb\n", output
  end

  def test_echo_escape_escape_char
    output = capture_stdout { execute('echo -e a\\eb') }
    assert_equal "a\eb\n", output
  end

  # \c stops output
  def test_echo_escape_c_stops_output
    output = capture_stdout { execute('echo -e hello\\cworld') }
    assert_equal 'hello', output  # No newline after \c
  end

  # Octal escape
  def test_echo_escape_octal
    output = capture_stdout { execute('echo -e \\0101') }  # 'A' in octal
    assert_equal "A\n", output
  end

  def test_echo_escape_octal_null
    output = capture_stdout { execute('echo -e a\\0b') }
    assert_equal "a\0b\n", output
  end

  # Hex escape
  def test_echo_escape_hex
    output = capture_stdout { execute('echo -e \\x41') }  # 'A' in hex
    assert_equal "A\n", output
  end

  def test_echo_escape_hex_lowercase
    output = capture_stdout { execute('echo -e \\x61') }  # 'a' in hex
    assert_equal "a\n", output
  end

  # Invalid option strings should be treated as arguments
  def test_echo_invalid_option_treated_as_argument
    output = capture_stdout { execute('echo -abc') }
    assert_equal "-abc\n", output
  end

  # Dash alone should be printed
  def test_echo_dash_alone
    output = capture_stdout { execute('echo -') }
    assert_equal "-\n", output
  end

  # Multiple valid option groups
  def test_echo_multiple_option_groups
    output = capture_stdout { execute('echo -n -e hello\\nworld') }
    assert_equal "hello\nworld", output
  end

  # -E after -e should disable escapes
  def test_echo_E_overrides_e
    output = capture_stdout { execute('echo -eE hello\\nworld') }
    assert_equal "hello\\nworld\n", output
  end

  # -e after -E should enable escapes
  def test_echo_e_overrides_E
    output = capture_stdout { execute('echo -Ee hello\\nworld') }
    assert_equal "hello\nworld\n", output
  end
end
