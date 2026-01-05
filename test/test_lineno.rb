# frozen_string_literal: true

require_relative 'test_helper'

class TestLINENO < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_lineno_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic LINENO functionality

  def test_lineno_starts_at_one
    assert_equal 1, @repl.lineno
  end

  def test_lineno_increments_with_commands
    initial = @repl.lineno
    execute('echo hello')
    assert_equal initial + 1, @repl.lineno
    execute('echo world')
    assert_equal initial + 2, @repl.lineno
  end

  def test_lineno_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $LINENO > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_lineno_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINENO} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_lineno_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Line: $LINENO\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'Line: 1', content
  end

  def test_lineno_increments_in_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo line1 > #{output_file}")
    execute("echo $LINENO >> #{output_file}")
    execute("echo $LINENO >> #{output_file}")
    lines = File.read(output_file).strip.split("\n")
    assert_equal 'line1', lines[0]
    assert_equal '2', lines[1]
    assert_equal '3', lines[2]
  end

  # Setting LINENO

  def test_set_lineno
    execute('LINENO=100')
    assert_equal 100, @repl.lineno
  end

  def test_lineno_continues_from_set_value
    execute('LINENO=50')
    execute('echo test')
    assert_equal 51, @repl.lineno
  end

  def test_lineno_not_stored_in_env
    assert_nil ENV['LINENO'], 'LINENO should not be stored in ENV'
    execute('echo $LINENO')
    assert_nil ENV['LINENO'], 'LINENO should still not be in ENV after access'
  end

  # Parameter expansion with LINENO

  def test_lineno_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINENO:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_lineno_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${LINENO:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'LINENO should be considered set'
  end

  # Arithmetic with LINENO

  def test_lineno_in_arithmetic
    execute('LINENO=10')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((LINENO + 5)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # LINENO is 10 (assignments don't increment LINENO), so 10+5=15
    assert_equal 15, value
  end

  # Edge cases

  def test_lineno_reset_multiple_times
    execute('LINENO=100')
    assert_equal 100, @repl.lineno
    execute('LINENO=1')
    assert_equal 1, @repl.lineno
    execute('LINENO=200')
    assert_equal 200, @repl.lineno
  end

  def test_lineno_zero
    execute('LINENO=0')
    assert_equal 0, @repl.lineno
    execute('echo test')
    assert_equal 1, @repl.lineno
  end

  def test_lineno_negative
    execute('LINENO=-5')
    assert_equal(-5, @repl.lineno)
    execute('echo test')
    assert_equal(-4, @repl.lineno)
  end

  def test_lineno_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    repl1.send(:execute, 'LINENO=100')
    repl2.send(:execute, 'LINENO=200')

    assert_equal 100, repl1.lineno
    assert_equal 200, repl2.lineno
  end

  def test_lineno_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $LINENO) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_lineno_multiple_on_same_line
    # Multiple LINENO references on same command should give same value
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $LINENO $LINENO > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal values[0], values[1], 'Multiple LINENO on same line should be equal'
  end
end
