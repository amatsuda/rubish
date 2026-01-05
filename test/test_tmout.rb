# frozen_string_literal: true

require_relative 'test_helper'

class TestTMOUT < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_tmout_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # TMOUT helper method tests

  def test_tmout_default_nil
    ENV.delete('TMOUT')
    assert_nil Rubish::Builtins.tmout
  end

  def test_tmout_integer_value
    ENV['TMOUT'] = '5'
    assert_equal 5.0, Rubish::Builtins.tmout
  end

  def test_tmout_float_value
    ENV['TMOUT'] = '2.5'
    assert_equal 2.5, Rubish::Builtins.tmout
  end

  def test_tmout_empty_string
    ENV['TMOUT'] = ''
    assert_nil Rubish::Builtins.tmout
  end

  def test_tmout_zero
    ENV['TMOUT'] = '0'
    assert_equal 0.0, Rubish::Builtins.tmout
  end

  # read builtin with TMOUT tests

  def test_read_with_tmout_success
    ENV['TMOUT'] = '5'
    File.write('input.txt', "hello\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['var'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal 'hello', ENV['var']
    end
  end

  def test_read_with_tmout_timeout
    ENV['TMOUT'] = '0.1'

    # Create a pipe that will never have data
    read_io, _write_io = IO.pipe

    result = nil
    Thread.new do
      sleep 0.5
      read_io.close rescue nil
    end

    original_stdin = $stdin
    $stdin = read_io
    result = Rubish::Builtins.run_read(['var'])
    $stdin = original_stdin

    assert_equal false, result
  end

  def test_read_explicit_timeout_overrides_tmout
    ENV['TMOUT'] = '10'  # Long timeout

    # Create a pipe that will never have data
    read_io, _write_io = IO.pipe

    result = nil
    start_time = Time.now
    Thread.new do
      sleep 1
      read_io.close rescue nil
    end

    original_stdin = $stdin
    $stdin = read_io
    result = Rubish::Builtins.run_read(['-t', '0.1', 'var'])
    $stdin = original_stdin
    elapsed = Time.now - start_time

    assert_equal false, result
    # Should timeout after ~0.1s, not 10s
    assert elapsed < 1.0, "Expected timeout after ~0.1s, but took #{elapsed}s"
  end

  def test_read_no_timeout_without_tmout
    ENV.delete('TMOUT')
    File.write('input.txt', "data\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['var'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal 'data', ENV['var']
    end
  end

  def test_read_tmout_zero_no_timeout
    ENV['TMOUT'] = '0'
    File.write('input.txt', "value\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['var'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal 'value', ENV['var']
    end
  end

  def test_read_tmout_with_nchars
    ENV['TMOUT'] = '5'
    File.write('input.txt', 'abcdef')

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['-n', '3', 'var'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal 'abc', ENV['var']
    end
  end

  def test_read_tmout_with_array
    ENV['TMOUT'] = '5'
    File.write('input.txt', "one two three\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['-a', 'arr'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal '3', ENV['arr_LENGTH']
      assert_equal 'one', ENV['arr_0']
    end
  end

  def test_read_tmout_negative_treated_as_no_timeout
    # Negative TMOUT should be treated as no timeout (like bash)
    ENV['TMOUT'] = '-1'
    File.write('input.txt', "test\n")

    File.open('input.txt', 'r') do |f|
      $stdin = f
      result = Rubish::Builtins.run_read(['var'])
      $stdin = STDIN
      assert_equal true, result
      assert_equal 'test', ENV['var']
    end
  end
end
