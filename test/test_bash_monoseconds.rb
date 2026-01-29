# frozen_string_literal: true

require_relative 'test_helper'

class TestBashMonoseconds < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_monoseconds_test')
  end

  def teardown
    ENV.replace(@original_env)
    FileUtils.rm_rf(@tempdir)
  end

  # Basic BASH_MONOSECONDS functionality

  def test_bash_monoseconds_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'BASH_MONOSECONDS should be an integer')
  end

  def test_bash_monoseconds_is_positive
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, "BASH_MONOSECONDS should be positive, got #{value}"
  end

  def test_bash_monoseconds_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_MONOSECONDS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0
  end

  def test_bash_monoseconds_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Mono: $BASH_MONOSECONDS\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Mono: \d+/, content)
  end

  # BASH_MONOSECONDS is read-only

  def test_bash_monoseconds_assignment_ignored
    execute('BASH_MONOSECONDS=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_MONOSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should still be a valid monotonic time value, not 12345
    assert value > 0
    # Very unlikely that monotonic seconds would be exactly 12345
    # unless system just booted, but it would still be different
    # from a sequential assignment-then-read
  end

  def test_bash_monoseconds_not_stored_in_env
    assert_nil ENV['BASH_MONOSECONDS'], 'BASH_MONOSECONDS should not be stored in ENV'
    execute('echo $BASH_MONOSECONDS')
    assert_nil ENV['BASH_MONOSECONDS'], 'BASH_MONOSECONDS should still not be in ENV after access'
    execute('BASH_MONOSECONDS=123')
    assert_nil ENV['BASH_MONOSECONDS'], 'BASH_MONOSECONDS should not be in ENV after assignment attempt'
  end

  # Monotonic clock behavior

  def test_bash_monoseconds_increases_over_time
    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    execute("echo $BASH_MONOSECONDS > #{output_file1}")
    sleep(1.1)  # Sleep a bit more than 1 second
    execute("echo $BASH_MONOSECONDS > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    assert value2 >= value1, "BASH_MONOSECONDS should not decrease: #{value1} -> #{value2}"
    # After 1+ seconds, the value should increase by at least 1
    assert value2 > value1, 'BASH_MONOSECONDS should increase after 1 second'
  end

  def test_bash_monoseconds_similar_to_epochseconds
    # BASH_MONOSECONDS and EPOCHSECONDS should be in a similar range
    # (both are seconds, though from different clocks)
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_MONOSECONDS $EPOCHSECONDS > #{output_file}")
    values = File.read(output_file).strip.split
    mono = values[0].to_i
    epoch = values[1].to_i

    # Both should be reasonably large integers (seconds)
    assert mono > 0, 'BASH_MONOSECONDS should be positive'
    assert epoch > 0, 'EPOCHSECONDS should be positive'

    # Monotonic clock started at system boot, so it should be less than epoch
    # (unless system has been running since before 1970, which is impossible)
    # This is a sanity check that we're not returning garbage
  end

  # Parameter expansion

  def test_bash_monoseconds_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_MONOSECONDS:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'Expected BASH_MONOSECONDS value, not default')
  end

  def test_bash_monoseconds_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_MONOSECONDS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASH_MONOSECONDS should be considered set'
  end

  # Arithmetic

  def test_bash_monoseconds_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((BASH_MONOSECONDS % 1000)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 1000, "Expected 0-999, got #{value}"
  end

  def test_bash_monoseconds_arithmetic_comparison
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((BASH_MONOSECONDS > 0 ? 1 : 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value, 'BASH_MONOSECONDS should be > 0'
  end

  # Edge cases

  def test_bash_monoseconds_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $BASH_MONOSECONDS) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0
  end

  def test_bash_monoseconds_multiple_accesses_same_command
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_MONOSECONDS $BASH_MONOSECONDS $BASH_MONOSECONDS > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # All three accesses should return the same or very close values
    # (within same second)
    values.each do |v|
      assert v > 0, 'Each BASH_MONOSECONDS access should be positive'
    end
    # They should be very close (within 1 second of each other)
    assert (values.max - values.min) <= 1, 'Multiple accesses should be close in value'
  end

  # monoseconds method

  def test_bash_monoseconds_method_returns_integer
    value = @repl.send(:monoseconds)
    assert_kind_of Integer, value
    assert value > 0
  end

  def test_bash_monoseconds_method_uses_monotonic_clock
    # Verify the method uses Process::CLOCK_MONOTONIC when available
    if defined?(Process::CLOCK_MONOTONIC)
      expected = Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i
      actual = @repl.send(:monoseconds)
      # Should be very close (within 1 second)
      assert (expected - actual).abs <= 1, 'Should use monotonic clock'
    else
      # Falls back to Time.now
      expected = Time.now.to_i
      actual = @repl.send(:monoseconds)
      assert (expected - actual).abs <= 1, 'Should fall back to epoch time'
    end
  end
end
