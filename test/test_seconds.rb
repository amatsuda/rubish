# frozen_string_literal: true

require_relative 'test_helper'

class TestSECONDS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_seconds_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def seconds
    @repl.send(:seconds)
  end

  # Basic SECONDS functionality

  def test_seconds_starts_at_zero
    # New REPL starts with SECONDS near 0
    assert seconds < 2, "Expected SECONDS to be near 0, got #{seconds}"
  end

  def test_seconds_increments
    initial = seconds
    sleep 1.1
    assert seconds > initial, 'Expected SECONDS to increment'
  end

  def test_seconds_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $SECONDS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected SECONDS >= 0'
    assert value < 10, 'Expected SECONDS < 10 for new REPL'
  end

  def test_seconds_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SECONDS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected SECONDS >= 0'
  end

  def test_seconds_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Time: $SECONDS\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Time: \d+/, content)
  end

  # Setting SECONDS

  def test_set_seconds_to_zero
    sleep 0.5
    execute('SECONDS=0')
    assert seconds < 2, "Expected SECONDS near 0 after reset, got #{seconds}"
  end

  def test_set_seconds_to_value
    execute('SECONDS=100')
    value = seconds
    assert value >= 100 && value < 110, "Expected SECONDS around 100, got #{value}"
  end

  def test_seconds_continues_from_set_value
    execute('SECONDS=50')
    sleep 1.1
    value = seconds
    assert value >= 51, "Expected SECONDS >= 51, got #{value}"
  end

  def test_seconds_not_stored_in_env
    # SECONDS should not appear in ENV
    assert_nil ENV['SECONDS'], 'SECONDS should not be stored in ENV'
    execute('echo $SECONDS')
    assert_nil ENV['SECONDS'], 'SECONDS should still not be in ENV after access'
  end

  # Parameter expansion with SECONDS

  def test_seconds_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SECONDS:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected SECONDS value, not default'
  end

  def test_seconds_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SECONDS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'SECONDS should be considered set'
  end

  # Arithmetic with SECONDS

  def test_seconds_in_arithmetic
    execute('SECONDS=10')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((SECONDS + 5)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 15, "Expected >= 15, got #{value}"
  end

  # Edge cases

  def test_seconds_reset_multiple_times
    execute('SECONDS=100')
    assert seconds >= 100
    execute('SECONDS=0')
    assert seconds < 5
    execute('SECONDS=200')
    assert seconds >= 200
  end

  def test_seconds_negative_value
    # Setting negative should work (bash allows this)
    execute('SECONDS=-10')
    value = seconds
    assert value >= -10 && value < 0, "Expected negative SECONDS, got #{value}"
  end

  def test_seconds_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $SECONDS) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected SECONDS >= 0 in subshell'
  end

  def test_seconds_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    repl1.send(:execute, 'SECONDS=100')
    repl2.send(:execute, 'SECONDS=200')

    assert repl1.send(:seconds) >= 100 && repl1.send(:seconds) < 150
    assert repl2.send(:seconds) >= 200 && repl2.send(:seconds) < 250
  end
end
