# frozen_string_literal: true

require_relative 'test_helper'

class TestAnsiCQuoting < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_ansi_c_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic escape sequences
  def test_newline_escape
    execute("echo $'hello\\nworld' > #{output_file}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_tab_escape
    execute("echo $'hello\\tworld' > #{output_file}")
    assert_equal "hello\tworld\n", File.read(output_file)
  end

  def test_carriage_return_escape
    execute("echo $'hello\\rworld' > #{output_file}")
    assert_equal "hello\rworld\n", File.read(output_file)
  end

  def test_backslash_escape
    execute("echo $'hello\\\\world' > #{output_file}")
    assert_equal "hello\\world\n", File.read(output_file)
  end

  def test_single_quote_escape
    execute("echo $'it\\'s' > #{output_file}")
    assert_equal "it's\n", File.read(output_file)
  end

  def test_double_quote_escape
    execute("echo $'say\\\"hello\\\"' > #{output_file}")
    assert_equal "say\"hello\"\n", File.read(output_file)
  end

  def test_alert_escape
    execute("echo $'bell\\a' > #{output_file}")
    assert_equal "bell\a\n", File.read(output_file)
  end

  def test_backspace_escape
    execute("echo $'back\\bspace' > #{output_file}")
    assert_equal "back\bspace\n", File.read(output_file)
  end

  def test_escape_escape
    execute("echo $'esc\\e' > #{output_file}")
    assert_equal "esc\e\n", File.read(output_file)
  end

  def test_form_feed_escape
    execute("echo $'form\\ffeed' > #{output_file}")
    assert_equal "form\ffeed\n", File.read(output_file)
  end

  def test_vertical_tab_escape
    execute("echo $'vert\\vtab' > #{output_file}")
    assert_equal "vert\vtab\n", File.read(output_file)
  end

  # Multiple escape sequences
  def test_multiple_escapes
    execute("echo $'a\\tb\\nc' > #{output_file}")
    assert_equal "a\tb\nc\n", File.read(output_file)
  end

  def test_consecutive_escapes
    execute("echo $'\\n\\n\\n' > #{output_file}")
    assert_equal "\n\n\n\n", File.read(output_file)
  end

  # Octal escapes
  def test_octal_escape
    # \101 = 'A' (octal 101 = decimal 65)
    execute("echo $'\\101' > #{output_file}")
    assert_equal "A\n", File.read(output_file)
  end

  def test_octal_escape_with_text
    execute("echo $'char:\\101' > #{output_file}")
    assert_equal "char:A\n", File.read(output_file)
  end

  # Hex escapes
  def test_hex_escape
    # \x41 = 'A' (hex 41 = decimal 65)
    execute("echo $'\\x41' > #{output_file}")
    assert_equal "A\n", File.read(output_file)
  end

  def test_hex_escape_lowercase
    execute("echo $'\\x61' > #{output_file}")
    assert_equal "a\n", File.read(output_file)
  end

  # Mixed content
  def test_mixed_with_regular_text
    execute("echo $'prefix\\nsuffix' > #{output_file}")
    assert_equal "prefix\nsuffix\n", File.read(output_file)
  end

  def test_only_escape
    execute("echo $'\\n' > #{output_file}")
    assert_equal "\n\n", File.read(output_file)
  end

  def test_empty_string
    execute("echo $'' > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # Assignment with ANSI-C quoting
  def test_variable_assignment
    execute("x=$'hello\\nworld'; echo \"$x\" > #{output_file}")
    assert_equal "hello\nworld\n", File.read(output_file)
  end

  def test_variable_assignment_tab
    execute("x=$'a\\tb'; echo \"$x\" > #{output_file}")
    assert_equal "a\tb\n", File.read(output_file)
  end

  # Multiple arguments
  def test_multiple_arguments
    execute("echo $'a\\nb' $'c\\nd' > #{output_file}")
    assert_equal "a\nb c\nd\n", File.read(output_file)
  end

  # Test that regular single quotes are not affected
  def test_regular_single_quotes_unchanged
    execute("echo 'hello\\nworld' > #{output_file}")
    # Regular single quotes should NOT process escape sequences
    assert_equal "hello\\nworld\n", File.read(output_file)
  end

  # Test unicode escape (bash 4.2+)
  def test_unicode_escape_u
    # \u0041 = 'A'
    execute("echo $'\\u0041' > #{output_file}")
    assert_equal "A\n", File.read(output_file)
  end

  def test_unicode_escape_U
    # \U00000041 = 'A'
    execute("echo $'\\U00000041' > #{output_file}")
    assert_equal "A\n", File.read(output_file)
  end

  # Test that unknown escapes pass through
  def test_unknown_escape_passed_through
    # \z is not a valid escape, should be kept as \z
    execute("echo $'\\z' > #{output_file}")
    content = File.read(output_file).chomp
    # Bash keeps the backslash for unknown escapes
    assert_equal '\\z', content
  end
end
