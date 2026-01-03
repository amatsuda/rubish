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
    output = capture_output { Rubish::Builtins.run('printf', []) }
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
end
