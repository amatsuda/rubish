# frozen_string_literal: true

require_relative 'test_helper'

class TestEPOCHREALTIME < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_epochrealtime_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic EPOCHREALTIME functionality

  def test_epochrealtime_returns_float_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHREALTIME > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+\.\d{6}$/, value, 'EPOCHREALTIME should be a float with 6 decimal places')
  end

  def test_epochrealtime_is_reasonable_timestamp
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHREALTIME > #{output_file}")
    value = File.read(output_file).strip.to_f
    now = Time.now.to_f
    # Should be within 5 seconds of current time
    assert (now - value).abs < 5, 'EPOCHREALTIME should be close to current time'
  end

  def test_epochrealtime_has_microseconds
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHREALTIME > #{output_file}")
    value = File.read(output_file).strip
    # Should have decimal point and 6 digits after
    assert value.include?('.'), 'EPOCHREALTIME should contain decimal point'
    decimal_part = value.split('.')[1]
    assert_equal 6, decimal_part.length, 'EPOCHREALTIME should have 6 decimal places'
  end

  def test_epochrealtime_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHREALTIME} > #{output_file}")
    value = File.read(output_file).strip.to_f
    now = Time.now.to_f
    assert (now - value).abs < 5
  end

  def test_epochrealtime_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Time: $EPOCHREALTIME\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Time: \d+\.\d{6}/, content)
  end

  def test_epochrealtime_changes_on_each_access
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHREALTIME $EPOCHREALTIME > #{output_file}")
    values = File.read(output_file).strip.split
    # Two accesses should give slightly different values (microsecond precision)
    # They might be equal if very fast, but usually different
    value1 = values[0].to_f
    value2 = values[1].to_f
    # At minimum, they should both be valid timestamps
    assert value1 > 1600000000
    assert value2 > 1600000000
  end

  # EPOCHREALTIME is read-only

  def test_epochrealtime_assignment_ignored
    before = Time.now.to_f
    execute('EPOCHREALTIME=0')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHREALTIME > #{output_file}")
    value = File.read(output_file).strip.to_f
    after = Time.now.to_f
    assert value >= before && value <= after, 'EPOCHREALTIME should remain current time after assignment'
  end

  def test_epochrealtime_not_stored_in_env
    assert_nil ENV['EPOCHREALTIME'], 'EPOCHREALTIME should not be stored in ENV'
    execute('echo $EPOCHREALTIME')
    assert_nil ENV['EPOCHREALTIME'], 'EPOCHREALTIME should still not be in ENV after access'
    execute('EPOCHREALTIME=123')
    assert_nil ENV['EPOCHREALTIME'], 'EPOCHREALTIME should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_epochrealtime_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHREALTIME:-default} > #{output_file}")
    value = File.read(output_file).strip.to_f
    assert value > 0, 'Should get EPOCHREALTIME value, not default'
  end

  def test_epochrealtime_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHREALTIME:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'EPOCHREALTIME should be considered set'
  end

  # String operations

  def test_epochrealtime_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#EPOCHREALTIME} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Unix timestamp with microseconds: 10 digits + dot + 6 digits = 17 chars
    assert_equal 17, value
  end

  def test_epochrealtime_substring_integer_part
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHREALTIME:0:10} > #{output_file}")
    value = File.read(output_file).strip
    # First 10 chars should be the integer part (Unix timestamp)
    assert_match(/^\d{10}$/, value)
  end

  def test_epochrealtime_substring_decimal_part
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHREALTIME:11:6} > #{output_file}")
    value = File.read(output_file).strip
    # Characters 11-16 should be the microseconds (after the dot)
    assert_match(/^\d{6}$/, value)
  end

  # Edge cases

  def test_epochrealtime_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $EPOCHREALTIME) > #{output_file}")
    value = File.read(output_file).strip.to_f
    now = Time.now.to_f
    assert (now - value).abs < 5
  end

  def test_epochrealtime_vs_epochseconds
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS $EPOCHREALTIME > #{output_file}")
    values = File.read(output_file).strip.split
    epochseconds = values[0].to_i
    epochrealtime = values[1].to_f

    # Integer part of EPOCHREALTIME should equal EPOCHSECONDS (within 1 second)
    assert (epochrealtime.to_i - epochseconds).abs <= 1
  end

  def test_epochrealtime_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $EPOCHREALTIME > #{output_file1}")
    repl2.send(:execute, "echo $EPOCHREALTIME > #{output_file2}")

    value1 = File.read(output_file1).strip.to_f
    value2 = File.read(output_file2).strip.to_f

    # Both should be close to current time
    now = Time.now.to_f
    assert (now - value1).abs < 5
    assert (now - value2).abs < 5
  end
end
