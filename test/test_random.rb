# frozen_string_literal: true

require_relative 'test_helper'

class TestRANDOM < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_random_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def random
    @repl.send(:random)
  end

  # Basic RANDOM functionality

  def test_random_returns_integer
    value = random
    assert_kind_of Integer, value
  end

  def test_random_in_range
    100.times do
      value = random
      assert value >= 0, "RANDOM should be >= 0, got #{value}"
      assert value < 32768, "RANDOM should be < 32768, got #{value}"
    end
  end

  def test_random_varies
    # Get multiple random values and ensure they're not all the same
    values = Array.new(10) { random }
    assert values.uniq.size > 1, 'RANDOM should return different values'
  end

  def test_random_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RANDOM > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected RANDOM >= 0'
    assert value < 32768, 'Expected RANDOM < 32768'
  end

  def test_random_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RANDOM} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 32768
  end

  def test_random_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Random: $RANDOM\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/Random: \d+/, content)
  end

  def test_random_each_access_different
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RANDOM $RANDOM $RANDOM > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # With 3 random values, at least 2 should differ (very high probability)
    assert values.uniq.size >= 2, 'Each RANDOM access should generate new value'
  end

  # Seeding RANDOM

  def test_seed_random_produces_reproducible_sequence
    execute('RANDOM=12345')
    values1 = Array.new(5) { random }

    execute('RANDOM=12345')
    values2 = Array.new(5) { random }

    assert_equal values1, values2, 'Same seed should produce same sequence'
  end

  def test_different_seeds_produce_different_sequences
    execute('RANDOM=11111')
    values1 = Array.new(5) { random }

    execute('RANDOM=22222')
    values2 = Array.new(5) { random }

    assert_not_equal values1, values2, 'Different seeds should produce different sequences'
  end

  def test_random_not_stored_in_env
    assert_nil ENV['RANDOM'], 'RANDOM should not be stored in ENV'
    execute('echo $RANDOM')
    assert_nil ENV['RANDOM'], 'RANDOM should still not be in ENV after access'
    execute('RANDOM=123')
    assert_nil ENV['RANDOM'], 'RANDOM should not be in ENV after seeding'
  end

  # Parameter expansion with RANDOM

  def test_random_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RANDOM:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, 'Expected RANDOM value, not default'
  end

  def test_random_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RANDOM:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RANDOM should be considered set'
  end

  # Arithmetic with RANDOM

  def test_random_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((RANDOM % 100)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 100, "Expected 0-99, got #{value}"
  end

  def test_random_modulo_in_arithmetic
    # Test that RANDOM % N gives values in expected range
    output_file = File.join(@tempdir, 'output.txt')
    10.times do |i|
      execute("echo $((RANDOM % 10)) >> #{output_file}")
    end
    values = File.read(output_file).strip.split("\n").map(&:to_i)
    values.each do |v|
      assert v >= 0 && v < 10, "Expected 0-9, got #{v}"
    end
  end

  # Edge cases

  def test_random_seed_zero
    execute('RANDOM=0')
    values = Array.new(3) { random }
    # Should still produce valid random numbers
    values.each do |v|
      assert v >= 0 && v < 32768
    end
  end

  def test_random_seed_negative
    # Negative seeds should still work
    execute('RANDOM=-1')
    value = random
    assert value >= 0 && value < 32768
  end

  def test_random_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    repl1.send(:execute, 'RANDOM=12345')
    repl2.send(:execute, 'RANDOM=12345')

    values1 = Array.new(3) { repl1.send(:random) }
    values2 = Array.new(3) { repl2.send(:random) }

    # Same seed should produce same sequence in different REPLs
    assert_equal values1, values2
  end

  def test_random_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $RANDOM) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0 && value < 32768
  end
end
