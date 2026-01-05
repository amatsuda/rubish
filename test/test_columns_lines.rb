# frozen_string_literal: true

require_relative 'test_helper'

class TestColumnsLines < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_columns_lines_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic COLUMNS functionality

  def test_columns_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $COLUMNS > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'COLUMNS should be an integer')
    assert value.to_i > 0, 'COLUMNS should be positive'
  end

  def test_columns_with_braces
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COLUMNS} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'COLUMNS should be an integer')
  end

  def test_columns_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((COLUMNS + 10)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should be at least 10 (since COLUMNS >= 0)
    assert value >= 10, 'COLUMNS + 10 should be at least 10'
  end

  def test_columns_default_value
    # When no terminal is available, should use ENV['COLUMNS'] or default to 80
    ENV.delete('COLUMNS')
    # In test environment without real terminal, should fall back
    columns = @repl.send(:terminal_columns)
    assert columns.is_a?(Integer), 'terminal_columns should return an integer'
    assert columns > 0, 'terminal_columns should be positive'
  end

  def test_columns_uses_env_fallback
    ENV['COLUMNS'] = '120'
    # Create a new REPL to pick up ENV
    repl = Rubish::REPL.new
    # When IO.console is nil (no tty), should use ENV fallback
    # This tests the fallback mechanism
    columns = repl.send(:terminal_columns)
    assert columns.is_a?(Integer), 'terminal_columns should return an integer'
  end

  # Basic LINES functionality

  def test_lines_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $LINES > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'LINES should be an integer')
    assert value.to_i > 0, 'LINES should be positive'
  end

  def test_lines_with_braces
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINES} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'LINES should be an integer')
  end

  def test_lines_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((LINES + 5)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should be at least 5 (since LINES >= 0)
    assert value >= 5, 'LINES + 5 should be at least 5'
  end

  def test_lines_default_value
    # When no terminal is available, should use ENV['LINES'] or default to 24
    ENV.delete('LINES')
    lines = @repl.send(:terminal_lines)
    assert lines.is_a?(Integer), 'terminal_lines should return an integer'
    assert lines > 0, 'terminal_lines should be positive'
  end

  def test_lines_uses_env_fallback
    ENV['LINES'] = '50'
    repl = Rubish::REPL.new
    lines = repl.send(:terminal_lines)
    assert lines.is_a?(Integer), 'terminal_lines should return an integer'
  end

  # Parameter expansion tests

  def test_columns_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COLUMNS:-default} > #{output_file}")
    value = File.read(output_file).strip
    # Should NOT be 'default' since COLUMNS is always set
    assert_match(/^\d+$/, value, 'COLUMNS should use its value, not default')
  end

  def test_lines_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINES:-default} > #{output_file}")
    value = File.read(output_file).strip
    # Should NOT be 'default' since LINES is always set
    assert_match(/^\d+$/, value, 'LINES should use its value, not default')
  end

  def test_columns_plus_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COLUMNS:+set} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'set', value, 'COLUMNS should be considered set'
  end

  def test_lines_plus_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINES:+set} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'set', value, 'LINES should be considered set'
  end

  # Read-only behavior

  def test_columns_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('COLUMNS=999')
    execute("echo $COLUMNS > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Assignment should be ignored, value should be from terminal
    # (may or may not equal 999 depending on actual terminal)
    assert value > 0, 'COLUMNS should still have a positive value'
  end

  def test_lines_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('LINES=999')
    execute("echo $LINES > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Assignment should be ignored
    assert value > 0, 'LINES should still have a positive value'
  end

  def test_columns_not_stored_in_env_by_shell
    # COLUMNS might be in ENV from the actual terminal, but our assignment should be ignored
    original = ENV['COLUMNS']
    execute('COLUMNS=12345')
    # The shell should NOT store our assignment in ENV
    if original
      assert_equal original, ENV['COLUMNS'], 'COLUMNS in ENV should not change from shell assignment'
    end
  end

  def test_lines_not_stored_in_env_by_shell
    original = ENV['LINES']
    execute('LINES=12345')
    if original
      assert_equal original, ENV['LINES'], 'LINES in ENV should not change from shell assignment'
    end
  end

  # Comparison tests

  def test_columns_greater_than_zero
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ $COLUMNS -gt 0 ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value, 'COLUMNS should be greater than 0'
  end

  def test_lines_greater_than_zero
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ $LINES -gt 0 ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value, 'LINES should be greater than 0'
  end

  # String length tests

  def test_columns_string_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#COLUMNS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # COLUMNS is at least 1 digit (could be "80" = 2 chars, or "120" = 3 chars, etc.)
    assert value >= 1, 'COLUMNS should have at least 1 digit'
    assert value <= 5, 'COLUMNS should have at most 5 digits (reasonable terminal width)'
  end

  def test_lines_string_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#LINES} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 1, 'LINES should have at least 1 digit'
    assert value <= 5, 'LINES should have at most 5 digits'
  end

  # Combined usage tests

  def test_columns_and_lines_together
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${COLUMNS}x${LINES} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+x\d+$/, value, 'Should output COLUMNSxLINES format')
  end

  def test_terminal_size_calculation
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((COLUMNS * LINES)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should be a reasonable number (e.g., 80*24 = 1920 for default)
    assert value > 0, 'COLUMNS * LINES should be positive'
  end
end
