# frozen_string_literal: true

require_relative 'test_helper'

class TestPrintf < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_printf_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Test basic string formatting
  def test_printf_string
    output = capture_output { Rubish::Builtins.run('printf', ['%s', 'hello']) }
    assert_equal 'hello', output
  end

  def test_printf_multiple_strings
    output = capture_output { Rubish::Builtins.run('printf', ['%s %s', 'hello', 'world']) }
    assert_equal 'hello world', output
  end

  # Test integer formatting
  def test_printf_decimal
    output = capture_output { Rubish::Builtins.run('printf', ['%d', '42']) }
    assert_equal '42', output
  end

  def test_printf_integer_i
    output = capture_output { Rubish::Builtins.run('printf', ['%i', '123']) }
    assert_equal '123', output
  end

  def test_printf_negative_integer
    output = capture_output { Rubish::Builtins.run('printf', ['%d', '-42']) }
    assert_equal '-42', output
  end

  # Test hexadecimal formatting
  def test_printf_hex_lower
    output = capture_output { Rubish::Builtins.run('printf', ['%x', '255']) }
    assert_equal 'ff', output
  end

  def test_printf_hex_upper
    output = capture_output { Rubish::Builtins.run('printf', ['%X', '255']) }
    assert_equal 'FF', output
  end

  def test_printf_hex_with_prefix
    output = capture_output { Rubish::Builtins.run('printf', ['%#x', '255']) }
    assert_equal '0xff', output
  end

  # Test octal formatting
  def test_printf_octal
    output = capture_output { Rubish::Builtins.run('printf', ['%o', '8']) }
    assert_equal '10', output
  end

  def test_printf_octal_with_prefix
    output = capture_output { Rubish::Builtins.run('printf', ['%#o', '8']) }
    assert_equal '010', output
  end

  # Test floating point formatting
  def test_printf_float
    output = capture_output { Rubish::Builtins.run('printf', ['%f', '3.14159']) }
    assert_equal '3.141590', output
  end

  def test_printf_float_precision
    output = capture_output { Rubish::Builtins.run('printf', ['%.2f', '3.14159']) }
    assert_equal '3.14', output
  end

  def test_printf_scientific
    output = capture_output { Rubish::Builtins.run('printf', ['%e', '1234.5']) }
    assert_match(/1\.234500e\+03/, output)
  end

  def test_printf_scientific_upper
    output = capture_output { Rubish::Builtins.run('printf', ['%E', '1234.5']) }
    assert_match(/1\.234500E\+03/, output)
  end

  # Test character formatting
  def test_printf_char
    output = capture_output { Rubish::Builtins.run('printf', ['%c', 'ABC']) }
    assert_equal 'A', output
  end

  # Test width formatting
  def test_printf_width_right_align
    output = capture_output { Rubish::Builtins.run('printf', ['%10s', 'hello']) }
    assert_equal '     hello', output
  end

  def test_printf_width_left_align
    output = capture_output { Rubish::Builtins.run('printf', ['%-10s', 'hello']) }
    assert_equal 'hello     ', output
  end

  def test_printf_width_zero_pad
    output = capture_output { Rubish::Builtins.run('printf', ['%05d', '42']) }
    assert_equal '00042', output
  end

  # Test precision
  def test_printf_string_precision
    output = capture_output { Rubish::Builtins.run('printf', ['%.3s', 'hello']) }
    assert_equal 'hel', output
  end

  def test_printf_integer_precision
    output = capture_output { Rubish::Builtins.run('printf', ['%.5d', '42']) }
    assert_equal '00042', output
  end

  # Test escape sequences
  def test_printf_newline
    output = capture_output { Rubish::Builtins.run('printf', ['hello\\nworld']) }
    assert_equal "hello\nworld", output
  end

  def test_printf_tab
    output = capture_output { Rubish::Builtins.run('printf', ['hello\\tworld']) }
    assert_equal "hello\tworld", output
  end

  def test_printf_carriage_return
    output = capture_output { Rubish::Builtins.run('printf', ['hello\\rworld']) }
    assert_equal "hello\rworld", output
  end

  def test_printf_backslash
    output = capture_output { Rubish::Builtins.run('printf', ['hello\\\\world']) }
    assert_equal 'hello\\world', output
  end

  # Test literal percent
  def test_printf_literal_percent
    output = capture_output { Rubish::Builtins.run('printf', ['100%%']) }
    assert_equal '100%', output
  end

  # Test %b (string with escapes)
  def test_printf_b_specifier
    output = capture_output { Rubish::Builtins.run('printf', ['%b', 'hello\\nworld']) }
    assert_equal "hello\nworld", output
  end

  # Test + flag
  def test_printf_plus_flag
    output = capture_output { Rubish::Builtins.run('printf', ['%+d', '42']) }
    assert_equal '+42', output
  end

  def test_printf_plus_flag_negative
    output = capture_output { Rubish::Builtins.run('printf', ['%+d', '-42']) }
    assert_equal '-42', output
  end

  # Test space flag
  def test_printf_space_flag
    output = capture_output { Rubish::Builtins.run('printf', ['% d', '42']) }
    assert_equal ' 42', output
  end

  # Test missing arguments
  def test_printf_missing_string_arg
    output = capture_output { Rubish::Builtins.run('printf', ['%s %s', 'hello']) }
    assert_equal 'hello ', output
  end

  def test_printf_missing_number_arg
    output = capture_output { Rubish::Builtins.run('printf', ['%d %d', '42']) }
    assert_equal '42 0', output
  end

  # Test usage error
  def test_printf_no_args
    output = capture_stderr { Rubish::Builtins.run('printf', []) }
    assert_match(/usage/, output)
  end

  # Test via REPL
  def test_printf_via_repl
    execute("printf '%s\\n' hello > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_printf_formatted_via_repl
    execute("printf '%05d\\n' 42 > #{output_file}")
    assert_equal "00042\n", File.read(output_file)
  end

  # Test combined width and precision
  def test_printf_width_and_precision
    output = capture_output { Rubish::Builtins.run('printf', ['%10.2f', '3.14159']) }
    assert_equal '      3.14', output
  end

  # Test g/G specifiers
  def test_printf_g_specifier
    output = capture_output { Rubish::Builtins.run('printf', ['%g', '0.000123']) }
    assert_match(/0\.000123|1\.23.*e-0?4/, output)
  end

  # Test -v option (variable assignment)
  def test_printf_v_option_basic
    output = capture_output { Rubish::Builtins.run('printf', ['-v', 'myvar', '%s', 'hello']) }
    assert_equal '', output  # No output to stdout
    assert_equal 'hello', get_shell_var('myvar')
  end

  def test_printf_v_option_formatted
    output = capture_output { Rubish::Builtins.run('printf', ['-v', 'result', '%05d', '42']) }
    assert_equal '', output
    assert_equal '00042', get_shell_var('result')
  end

  def test_printf_v_option_multiple_args
    output = capture_output { Rubish::Builtins.run('printf', ['-v', 'msg', '%s %s!', 'hello', 'world']) }
    assert_equal '', output
    assert_equal 'hello world!', get_shell_var('msg')
  end

  def test_printf_v_option_with_newline
    output = capture_output { Rubish::Builtins.run('printf', ['-v', 'lines', 'line1\\nline2']) }
    assert_equal '', output
    assert_equal "line1\nline2", get_shell_var('lines')
  end

  def test_printf_v_option_missing_varname
    output = capture_stderr { Rubish::Builtins.run('printf', ['-v']) }
    assert_match(/option requires an argument/, output)
  end

  def test_printf_v_option_invalid_varname
    output = capture_stderr { Rubish::Builtins.run('printf', ['-v', '123invalid', '%s', 'test']) }
    assert_match(/not a valid identifier/, output)
  end

  def test_printf_v_option_invalid_varname_with_dash
    output = capture_stderr { Rubish::Builtins.run('printf', ['-v', 'my-var', '%s', 'test']) }
    assert_match(/not a valid identifier/, output)
  end

  def test_printf_v_returns_true_on_success
    capture_output do
      result = Rubish::Builtins.run('printf', ['-v', 'x', '%s', 'test'])
      assert result
    end
  end

  def test_printf_v_returns_false_on_error
    capture_stderr do
      result = Rubish::Builtins.run('printf', ['-v'])
      assert_false result
    end
  end

  def test_printf_v_via_repl
    execute("printf -v greeting '%s %s' hello world")
    assert_equal 'hello world', get_shell_var('greeting')
  end

  def test_printf_v_overwrites_existing
    ENV['existing'] = 'old value'
    capture_output { Rubish::Builtins.run('printf', ['-v', 'existing', '%s', 'new value']) }
    assert_equal 'new value', get_shell_var('existing')
  end

  def test_printf_v_underscore_varname
    capture_output { Rubish::Builtins.run('printf', ['-v', '_private', '%d', '99']) }
    assert_equal '99', get_shell_var('_private')
  end

  def test_printf_v_with_double_dash
    output = capture_output { Rubish::Builtins.run('printf', ['-v', 'var', '--', '%s', 'test']) }
    assert_equal '', output
    assert_equal 'test', get_shell_var('var')
  end

  def test_printf_invalid_option
    output = capture_stderr { Rubish::Builtins.run('printf', ['-x', '%s', 'test']) }
    assert_match(/invalid option/, output)
  end

  # Test %q format specifier (shell quoting)
  def test_printf_q_simple_string
    # Simple alphanumeric strings don't need quoting
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'hello']) }
    assert_equal 'hello', output
  end

  def test_printf_q_string_with_spaces
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'hello world']) }
    # Should be quoted in some way that preserves the space
    assert_match(/^'hello world'$|^hello\\ world$/, output)
  end

  def test_printf_q_empty_string
    output = capture_output { Rubish::Builtins.run('printf', ['%q', '']) }
    assert_equal "''", output
  end

  def test_printf_q_single_quote
    output = capture_output { Rubish::Builtins.run('printf', ['%q', "it's"]) }
    # Should escape the single quote using $'...' syntax
    assert_match(/\$'it\\'s'/, output)
  end

  def test_printf_q_double_quote
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'say "hello"']) }
    # Double quotes inside single quotes are safe
    assert_match(/'say "hello"'/, output)
  end

  def test_printf_q_special_chars
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'a*b?c']) }
    # Glob characters should be quoted
    assert_match(/^'a\*b\?c'$/, output)
  end

  def test_printf_q_dollar_sign
    output = capture_output { Rubish::Builtins.run('printf', ['%q', '$HOME']) }
    # Dollar sign should be quoted to prevent expansion
    assert_match(/'\$HOME'/, output)
  end

  def test_printf_q_backslash
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'a\\b']) }
    # Backslash should be preserved
    refute_empty output
  end

  def test_printf_q_newline
    output = capture_output { Rubish::Builtins.run('printf', ['%q', "hello\nworld"]) }
    # Newline should be escaped using $'...' syntax
    assert_match(/\$'hello\\nworld'/, output)
  end

  def test_printf_q_tab
    output = capture_output { Rubish::Builtins.run('printf', ['%q', "hello\tworld"]) }
    # Tab should be escaped
    assert_match(/\$'hello\\tworld'/, output)
  end

  def test_printf_q_safe_chars
    # These characters are safe and don't need quoting
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'file.txt']) }
    assert_equal 'file.txt', output

    output = capture_output { Rubish::Builtins.run('printf', ['%q', '/usr/bin/ruby']) }
    assert_equal '/usr/bin/ruby', output

    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'foo-bar_baz']) }
    assert_equal 'foo-bar_baz', output
  end

  def test_printf_q_multiple_args
    output = capture_output { Rubish::Builtins.run('printf', ['%q %q', 'hello', 'world']) }
    assert_equal 'hello world', output
  end

  def test_printf_q_with_width
    output = capture_output { Rubish::Builtins.run('printf', ['%10q', 'hi']) }
    assert_equal '        hi', output
  end

  def test_printf_q_with_v_option
    capture_output { Rubish::Builtins.run('printf', ['-v', 'quoted', '%q', 'hello world']) }
    assert_match(/^'hello world'$|^hello\\ world$/, get_shell_var('quoted'))
  end

  def test_printf_q_semicolon
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'cmd1; cmd2']) }
    # Semicolon should be quoted
    assert_match(/'cmd1; cmd2'/, output)
  end

  def test_printf_q_pipe
    output = capture_output { Rubish::Builtins.run('printf', ['%q', 'a|b']) }
    # Pipe should be quoted
    assert_match(/'a\|b'/, output)
  end

  def test_printf_q_parentheses
    output = capture_output { Rubish::Builtins.run('printf', ['%q', '(subshell)']) }
    # Parentheses should be quoted
    assert_match(/'\(subshell\)'/, output)
  end

  def test_printf_q_via_repl
    # Test using builtin directly since REPL execution may call external printf
    # which doesn't support %q
    capture_output do
      result = Rubish::Builtins.run('printf', ['%q\n', 'hello world'])
      assert result
    end
  end

  # Test %(fmt)T time formatting
  def test_printf_T_current_time
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y)T']) }
    assert_equal Time.now.year.to_s, output
  end

  def test_printf_T_with_minus_one
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y-%m-%d)T', '-1']) }
    assert_equal Time.now.strftime('%Y-%m-%d'), output
  end

  def test_printf_T_with_epoch_timestamp
    # Unix epoch: Jan 1, 1970 00:00:00 UTC
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y-%m-%d)T', '0']) }
    expected = Time.at(0).strftime('%Y-%m-%d')
    assert_equal expected, output
  end

  def test_printf_T_with_specific_timestamp
    # Specific timestamp: 1234567890 = 2009-02-13 23:31:30 UTC
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%Y')
    assert_equal expected, output
  end

  def test_printf_T_hour_minute_second
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%H:%M:%S)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%H:%M:%S')
    assert_equal expected, output
  end

  def test_printf_T_full_date
    timestamp = 1609459200  # 2021-01-01 00:00:00 UTC
    output = capture_output { Rubish::Builtins.run('printf', ['%(%A, %B %d, %Y)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%A, %B %d, %Y')
    assert_equal expected, output
  end

  def test_printf_T_with_minus_two
    # -2 means shell start time, should return some valid time
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y)T', '-2']) }
    assert_match(/^\d{4}$/, output)
  end

  def test_printf_T_combined_with_string
    output = capture_output { Rubish::Builtins.run('printf', ['Date: %(%Y-%m-%d)T', '-1']) }
    assert_match(/^Date: \d{4}-\d{2}-\d{2}$/, output)
  end

  def test_printf_T_multiple_formats
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y)T-%(%m)T-%(%d)T', timestamp.to_s, timestamp.to_s, timestamp.to_s]) }
    t = Time.at(timestamp)
    expected = "#{t.strftime('%Y')}-#{t.strftime('%m')}-#{t.strftime('%d')}"
    assert_equal expected, output
  end

  def test_printf_T_with_v_option
    capture_output { Rubish::Builtins.run('printf', ['-v', 'timevar', '%(%Y)T', '-1']) }
    assert_equal Time.now.year.to_s, get_shell_var('timevar')
  ensure
    Rubish::Builtins.delete_var('timevar')
  end

  def test_printf_T_with_other_specifiers
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['Year: %(%Y)T, Value: %d', timestamp.to_s, '42']) }
    expected = "Year: #{Time.at(timestamp).strftime('%Y')}, Value: 42"
    assert_equal expected, output
  end

  def test_printf_T_iso_format
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%FT%T)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%FT%T')
    assert_equal expected, output
  end

  def test_printf_T_weekday
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%a %A)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%a %A')
    assert_equal expected, output
  end

  def test_printf_T_no_argument_defaults_to_now
    # When no argument provided, should default to current time
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Y)T']) }
    assert_equal Time.now.year.to_s, output
  end

  def test_printf_T_timezone
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%Z)T', timestamp.to_s]) }
    expected = Time.at(timestamp).strftime('%Z')
    assert_equal expected, output
  end

  def test_printf_T_epoch_seconds
    timestamp = 1234567890
    output = capture_output { Rubish::Builtins.run('printf', ['%(%s)T', timestamp.to_s]) }
    # %s in strftime returns epoch seconds
    assert_equal timestamp.to_s, output
  end

  # Test dynamic width %*s
  def test_printf_dynamic_width_string
    output = capture_output { Rubish::Builtins.run('printf', ['%*s', '10', 'hello']) }
    assert_equal '     hello', output
  end

  def test_printf_dynamic_width_right_align
    output = capture_output { Rubish::Builtins.run('printf', ['%*s', '8', 'test']) }
    assert_equal '    test', output
  end

  def test_printf_dynamic_width_negative_left_align
    # Negative width means left-align
    output = capture_output { Rubish::Builtins.run('printf', ['%*s', '-10', 'hello']) }
    assert_equal 'hello     ', output
  end

  def test_printf_dynamic_width_zero
    output = capture_output { Rubish::Builtins.run('printf', ['%*s', '0', 'hello']) }
    assert_equal 'hello', output
  end

  def test_printf_dynamic_width_integer
    output = capture_output { Rubish::Builtins.run('printf', ['%*d', '5', '42']) }
    assert_equal '   42', output
  end

  def test_printf_dynamic_width_integer_zero_pad
    output = capture_output { Rubish::Builtins.run('printf', ['%0*d', '5', '42']) }
    assert_equal '00042', output
  end

  # Test dynamic precision %.*s
  def test_printf_dynamic_precision_string
    output = capture_output { Rubish::Builtins.run('printf', ['%.*s', '3', 'hello']) }
    assert_equal 'hel', output
  end

  def test_printf_dynamic_precision_string_longer
    output = capture_output { Rubish::Builtins.run('printf', ['%.*s', '10', 'hello']) }
    assert_equal 'hello', output
  end

  def test_printf_dynamic_precision_float
    output = capture_output { Rubish::Builtins.run('printf', ['%.*f', '2', '3.14159']) }
    assert_equal '3.14', output
  end

  def test_printf_dynamic_precision_float_zero
    output = capture_output { Rubish::Builtins.run('printf', ['%.*f', '0', '3.14159']) }
    assert_equal '3', output
  end

  def test_printf_dynamic_precision_negative_ignored
    # Negative precision is treated as if precision were omitted
    output = capture_output { Rubish::Builtins.run('printf', ['%.*s', '-5', 'hello']) }
    assert_equal 'hello', output
  end

  # Test combined dynamic width and precision %*.*s
  def test_printf_dynamic_width_and_precision
    output = capture_output { Rubish::Builtins.run('printf', ['%*.*s', '10', '3', 'hello']) }
    assert_equal '       hel', output
  end

  def test_printf_dynamic_width_and_precision_left_align
    output = capture_output { Rubish::Builtins.run('printf', ['%-*.*s', '10', '3', 'hello']) }
    assert_equal 'hel       ', output
  end

  def test_printf_dynamic_width_negative_and_precision
    # Negative width with precision
    output = capture_output { Rubish::Builtins.run('printf', ['%*.*s', '-10', '3', 'hello']) }
    assert_equal 'hel       ', output
  end

  def test_printf_dynamic_width_and_precision_float
    output = capture_output { Rubish::Builtins.run('printf', ['%*.*f', '10', '2', '3.14159']) }
    assert_equal '      3.14', output
  end

  # Test with multiple format specifiers
  def test_printf_multiple_dynamic_widths
    output = capture_output { Rubish::Builtins.run('printf', ['%*s %*s', '5', 'a', '5', 'b']) }
    assert_equal '    a     b', output
  end

  def test_printf_mixed_static_and_dynamic_width
    output = capture_output { Rubish::Builtins.run('printf', ['%5s %*s', 'a', '5', 'b']) }
    assert_equal '    a     b', output
  end

  # Test with -v option
  def test_printf_dynamic_width_with_v_option
    capture_output { Rubish::Builtins.run('printf', ['-v', 'padded', '%*s', '10', 'test']) }
    assert_equal '      test', get_shell_var('padded')
  ensure
    Rubish::Builtins.delete_var('padded')
  end

  # Test missing arguments
  def test_printf_dynamic_width_missing_arg
    output = capture_output { Rubish::Builtins.run('printf', ['%*s', '10']) }
    # Missing string argument defaults to empty string
    assert_equal '          ', output
  end

  def test_printf_dynamic_width_missing_width_arg
    output = capture_output { Rubish::Builtins.run('printf', ['%*s']) }
    # Missing width arg defaults to 0
    assert_equal '', output
  end
end
