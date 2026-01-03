# frozen_string_literal: true

require_relative 'test_helper'

class TestTimes < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_times_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test times is a builtin
  def test_times_is_builtin
    assert Rubish::Builtins.builtin?('times')
  end

  # Test times returns true
  def test_times_returns_true
    capture_output do
      result = Rubish::Builtins.run('times', [])
      assert result
    end
  end

  # Test times outputs two lines
  def test_times_output_format
    output = capture_output { Rubish::Builtins.run('times', []) }
    lines = output.strip.split("\n")
    assert_equal 2, lines.length
  end

  # Test times output contains time format
  def test_times_output_contains_time_format
    output = capture_output { Rubish::Builtins.run('times', []) }
    # Should contain format like 0m0.001s
    assert_match(/\d+m[\d.]+s/, output)
  end

  # Test first line is shell times
  def test_times_first_line_shell_times
    output = capture_output { Rubish::Builtins.run('times', []) }
    lines = output.strip.split("\n")
    # First line: user and system time for shell
    assert_match(/\d+m[\d.]+s \d+m[\d.]+s/, lines[0])
  end

  # Test second line is children times
  def test_times_second_line_children_times
    output = capture_output { Rubish::Builtins.run('times', []) }
    lines = output.strip.split("\n")
    # Second line: user and system time for children
    assert_match(/\d+m[\d.]+s \d+m[\d.]+s/, lines[1])
  end

  # Test type identifies times as builtin
  def test_type_identifies_times_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['times']) }
    assert_match(/times is a shell builtin/, output)
  end

  # Test times via REPL
  def test_times_via_repl
    output = capture_output { execute('times') }
    lines = output.strip.split("\n")
    assert_equal 2, lines.length
  end

  # Test times ignores arguments
  def test_times_ignores_arguments
    output = capture_output { Rubish::Builtins.run('times', ['ignored', 'args']) }
    lines = output.strip.split("\n")
    assert_equal 2, lines.length
  end
end
