# frozen_string_literal: true

require_relative 'test_helper'

class TestRubishMonoseconds < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_monoseconds_test')
  end

  def teardown
    ENV.replace(@original_env)
    FileUtils.rm_rf(@tempdir)
  end

  # Basic RUBISH_MONOSECONDS functionality

  def test_rubish_monoseconds_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'RUBISH_MONOSECONDS should be an integer')
  end

  def test_rubish_monoseconds_is_positive
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, "RUBISH_MONOSECONDS should be positive, got #{value}"
  end

  def test_rubish_monoseconds_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_MONOSECONDS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0
  end

  def test_rubish_monoseconds_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Mono: $RUBISH_MONOSECONDS\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Mono: \d+/, content)
  end

  # RUBISH_MONOSECONDS is read-only

  def test_rubish_monoseconds_assignment_ignored
    execute('RUBISH_MONOSECONDS=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should still be a valid monotonic time value, not 12345
    assert value > 0
  end

  def test_rubish_monoseconds_not_stored_in_env
    assert_nil ENV['RUBISH_MONOSECONDS'], 'RUBISH_MONOSECONDS should not be stored in ENV'
    execute('echo $RUBISH_MONOSECONDS')
    assert_nil ENV['RUBISH_MONOSECONDS'], 'RUBISH_MONOSECONDS should still not be in ENV after access'
    execute('RUBISH_MONOSECONDS=123')
    assert_nil ENV['RUBISH_MONOSECONDS'], 'RUBISH_MONOSECONDS should not be in ENV after assignment attempt'
  end

  # RUBISH_MONOSECONDS equals BASH_MONOSECONDS

  def test_rubish_monoseconds_equals_bash_monoseconds
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_MONOSECONDS $BASH_MONOSECONDS > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # Both should be the same or very close (within 1 second)
    assert_equal 2, values.length
    assert (values[0] - values[1]).abs <= 1, 'RUBISH_MONOSECONDS and BASH_MONOSECONDS should be equal'
  end

  def test_rubish_and_bash_monoseconds_braced
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_MONOSECONDS} ${BASH_MONOSECONDS} > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    assert_equal 2, values.length
    assert (values[0] - values[1]).abs <= 1
  end

  # Monotonic clock behavior

  def test_rubish_monoseconds_increases_over_time
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    execute("echo $RUBISH_MONOSECONDS > #{output_file1}")
    sleep(1.1)  # Sleep a bit more than 1 second
    execute("echo $RUBISH_MONOSECONDS > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    assert value2 >= value1, "RUBISH_MONOSECONDS should not decrease: #{value1} -> #{value2}"
    assert value2 > value1, 'RUBISH_MONOSECONDS should increase after 1 second'
  end

  # Parameter expansion

  def test_rubish_monoseconds_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_MONOSECONDS:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'Expected RUBISH_MONOSECONDS value, not default')
  end

  def test_rubish_monoseconds_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_MONOSECONDS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RUBISH_MONOSECONDS should be considered set'
  end

  def test_rubish_monoseconds_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_MONOSECONDS} > #{output_file}")
    length = File.read(output_file).strip.to_i
    # Monotonic seconds should have several digits
    assert length > 0, 'RUBISH_MONOSECONDS length should be greater than 0'
  end

  # Arithmetic

  def test_rubish_monoseconds_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((RUBISH_MONOSECONDS % 1000)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 1000, "Expected 0-999, got #{value}"
  end

  def test_rubish_monoseconds_arithmetic_comparison
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((RUBISH_MONOSECONDS > 0 ? 1 : 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value, 'RUBISH_MONOSECONDS should be > 0'
  end

  # Edge cases

  def test_rubish_monoseconds_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $RUBISH_MONOSECONDS) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0
  end

  def test_rubish_monoseconds_multiple_accesses_same_command
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_MONOSECONDS $RUBISH_MONOSECONDS $RUBISH_MONOSECONDS > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # All three accesses should return the same or very close values
    values.each do |v|
      assert v > 0, 'Each RUBISH_MONOSECONDS access should be positive'
    end
    # They should be very close (within 1 second of each other)
    assert (values.max - values.min) <= 1, 'Multiple accesses should be close in value'
  end
end
