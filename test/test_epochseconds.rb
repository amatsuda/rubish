# frozen_string_literal: true

require_relative 'test_helper'

class TestEPOCHSECONDS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_epochseconds_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic EPOCHSECONDS functionality

  def test_epochseconds_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, "EPOCHSECONDS should be a positive integer, got #{value}"
  end

  def test_epochseconds_is_reasonable_timestamp
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    now = Time.now.to_i
    # Should be within 5 seconds of current time
    assert (now - value).abs < 5, 'EPOCHSECONDS should be close to current time'
  end

  def test_epochseconds_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHSECONDS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    now = Time.now.to_i
    assert (now - value).abs < 5
  end

  def test_epochseconds_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Time: $EPOCHSECONDS\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Time: \d+/, content)
  end

  def test_epochseconds_increments_over_time
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS > #{output_file}")
    value1 = File.read(output_file).strip.to_i
    sleep 1.1
    execute("echo $EPOCHSECONDS > #{output_file}")
    value2 = File.read(output_file).strip.to_i
    assert value2 > value1, 'EPOCHSECONDS should increment over time'
  end

  # EPOCHSECONDS is read-only

  def test_epochseconds_assignment_ignored
    before = Time.now.to_i
    execute('EPOCHSECONDS=0')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    after = Time.now.to_i
    assert value >= before && value <= after, 'EPOCHSECONDS should remain current time after assignment'
  end

  def test_epochseconds_not_stored_in_env
    assert_nil ENV['EPOCHSECONDS'], 'EPOCHSECONDS should not be stored in ENV'
    execute('echo $EPOCHSECONDS')
    assert_nil ENV['EPOCHSECONDS'], 'EPOCHSECONDS should still not be in ENV after access'
    execute('EPOCHSECONDS=123')
    assert_nil ENV['EPOCHSECONDS'], 'EPOCHSECONDS should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_epochseconds_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHSECONDS:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, 'Should get EPOCHSECONDS value, not default'
  end

  def test_epochseconds_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHSECONDS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'EPOCHSECONDS should be considered set'
  end

  # String operations

  def test_epochseconds_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#EPOCHSECONDS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Unix timestamp is 10 digits (until 2286)
    assert_equal 10, value
  end

  def test_epochseconds_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EPOCHSECONDS:0:4} > #{output_file}")
    value = File.read(output_file).strip
    # First 4 digits of current timestamp
    assert_match(/^\d{4}$/, value)
  end

  # Arithmetic

  def test_epochseconds_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((EPOCHSECONDS + 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    now = Time.now.to_i
    assert (now - value).abs < 5
  end

  def test_epochseconds_arithmetic_difference
    output_file = File.join(@tempdir, 'output.txt')
    # Calculate difference from a known timestamp
    execute("echo $((EPOCHSECONDS - 1600000000)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    expected = Time.now.to_i - 1600000000
    assert (expected - value).abs < 5
  end

  # Edge cases

  def test_epochseconds_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $EPOCHSECONDS) > #{output_file}")
    value = File.read(output_file).strip.to_i
    now = Time.now.to_i
    assert (now - value).abs < 5
  end

  def test_epochseconds_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $EPOCHSECONDS > #{output_file1}")
    repl2.send(:execute, "echo $EPOCHSECONDS > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # Both should be close to current time
    now = Time.now.to_i
    assert (now - value1).abs < 5
    assert (now - value2).abs < 5
  end

  def test_epochseconds_vs_seconds
    # EPOCHSECONDS is Unix timestamp, SECONDS is elapsed time since shell start
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EPOCHSECONDS $SECONDS > #{output_file}")
    values = File.read(output_file).strip.split
    epochseconds = values[0].to_i
    seconds = values[1].to_i

    # EPOCHSECONDS should be much larger than SECONDS
    assert epochseconds > 1600000000, 'EPOCHSECONDS should be Unix timestamp'
    assert seconds < 10, 'SECONDS should be small for new REPL'
  end
end
