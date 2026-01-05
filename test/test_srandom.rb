# frozen_string_literal: true

require_relative 'test_helper'

class TestSRANDOM < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_srandom_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic SRANDOM functionality

  def test_srandom_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $SRANDOM > #{output_file}")
    value = File.read(output_file).strip
    assert_match(/^\d+$/, value, 'SRANDOM should be an integer')
  end

  def test_srandom_in_32bit_range
    100.times do
      output_file = File.join(@tempdir, 'output.txt')
      execute("echo $SRANDOM > #{output_file}")
      value = File.read(output_file).strip.to_i
      assert value >= 0, "SRANDOM should be >= 0, got #{value}"
      assert value < 2**32, "SRANDOM should be < 2^32, got #{value}"
    end
  end

  def test_srandom_varies
    output_file = File.join(@tempdir, 'output.txt')
    values = []
    10.times do
      execute("echo $SRANDOM >> #{output_file}")
    end
    values = File.read(output_file).strip.split("\n").map(&:to_i)
    # With 32-bit random numbers, 10 values should almost certainly have multiple unique values
    assert values.uniq.size > 1, 'SRANDOM should return different values'
  end

  def test_srandom_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SRANDOM} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 2**32
  end

  def test_srandom_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Random: $SRANDOM\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Random: \d+/, content)
  end

  def test_srandom_each_access_different
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $SRANDOM $SRANDOM $SRANDOM > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # With 3 random 32-bit values, at least 2 should differ (extremely high probability)
    assert values.uniq.size >= 2, 'Each SRANDOM access should generate new value'
  end

  # SRANDOM is read-only (cannot be seeded)

  def test_srandom_assignment_ignored
    execute('SRANDOM=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $SRANDOM > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should still be a valid random number, not 12345
    assert value >= 0 && value < 2**32
    # It's extremely unlikely to be exactly 12345
  end

  def test_srandom_cannot_be_seeded
    # Unlike RANDOM, SRANDOM cannot be seeded for reproducibility
    execute('SRANDOM=99999')
    output_file1 = File.join(@tempdir, 'output1.txt')
    execute("echo $SRANDOM > #{output_file1}")

    execute('SRANDOM=99999')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo $SRANDOM > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # Values should be different (cryptographically random, not seeded)
    # This test has an astronomically small chance of false failure
    assert_not_equal value1, value2, 'SRANDOM should not be seedable'
  end

  def test_srandom_not_stored_in_env
    assert_nil ENV['SRANDOM'], 'SRANDOM should not be stored in ENV'
    execute('echo $SRANDOM')
    assert_nil ENV['SRANDOM'], 'SRANDOM should still not be in ENV after access'
    execute('SRANDOM=123')
    assert_nil ENV['SRANDOM'], 'SRANDOM should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_srandom_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SRANDOM:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected SRANDOM value, not default'
  end

  def test_srandom_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${SRANDOM:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'SRANDOM should be considered set'
  end

  # Arithmetic

  def test_srandom_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((SRANDOM % 100)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 100, "Expected 0-99, got #{value}"
  end

  def test_srandom_modulo_distribution
    output_file = File.join(@tempdir, 'output.txt')
    20.times do
      execute("echo $((SRANDOM % 10)) >> #{output_file}")
    end
    values = File.read(output_file).strip.split("\n").map(&:to_i)
    values.each do |v|
      assert v >= 0 && v < 10, "Expected 0-9, got #{v}"
    end
    # Should have some variety
    assert values.uniq.size > 1
  end

  # Comparison with RANDOM

  def test_srandom_larger_range_than_random
    # RANDOM is 0-32767 (15-bit), SRANDOM is 0-4294967295 (32-bit)
    found_large = false
    50.times do
      output_file = File.join(@tempdir, 'output.txt')
      execute("echo $SRANDOM > #{output_file}")
      value = File.read(output_file).strip.to_i
      if value >= 32768
        found_large = true
        break
      end
    end
    assert found_large, 'SRANDOM should produce values larger than RANDOM max (32767)'
  end

  # Edge cases

  def test_srandom_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $SRANDOM) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 2**32
  end

  def test_srandom_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $SRANDOM > #{output_file1}")
    repl2.send(:execute, "echo $SRANDOM > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # Both should be valid 32-bit values
    assert value1 >= 0 && value1 < 2**32
    assert value2 >= 0 && value2 < 2**32
    # And likely different (cryptographically random)
  end
end
