# frozen_string_literal: true

require_relative 'test_helper'

class TestCaller < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_caller_test')
    Rubish::Builtins.clear_call_stack
  end

  def teardown
    Rubish::Builtins.clear_call_stack
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test caller is a builtin
  def test_caller_is_builtin
    assert Rubish::Builtins.builtin?('caller')
  end

  # Test caller with empty stack returns false
  def test_caller_empty_stack
    result = Rubish::Builtins.run('caller', [])
    assert_false result
  end

  # Test caller displays top frame
  def test_caller_displays_frame
    Rubish::Builtins.push_call_frame(10, 'main', 'script.sh')
    Rubish::Builtins.push_call_frame(25, 'foo', 'script.sh')

    output = capture_output do
      result = Rubish::Builtins.run('caller', [])
      assert result
    end
    assert_equal "25 foo script.sh\n", output
  end

  # Test caller with frame number
  def test_caller_with_frame_number
    Rubish::Builtins.push_call_frame(10, 'main', 'script.sh')
    Rubish::Builtins.push_call_frame(25, 'foo', 'script.sh')
    Rubish::Builtins.push_call_frame(42, 'bar', 'lib.sh')

    # Frame 0 is the most recent
    output = capture_output { Rubish::Builtins.run('caller', ['0']) }
    assert_equal "42 bar lib.sh\n", output

    # Frame 1 is the caller of the current function
    output = capture_output { Rubish::Builtins.run('caller', ['1']) }
    assert_equal "25 foo script.sh\n", output

    # Frame 2 is even further back
    output = capture_output { Rubish::Builtins.run('caller', ['2']) }
    assert_equal "10 main script.sh\n", output
  end

  # Test caller with out of range frame
  def test_caller_out_of_range
    Rubish::Builtins.push_call_frame(10, 'main', 'script.sh')

    result = Rubish::Builtins.run('caller', ['5'])
    assert_false result
  end

  # Test caller with invalid number
  def test_caller_invalid_number
    Rubish::Builtins.push_call_frame(10, 'main', 'script.sh')

    output = capture_output do
      result = Rubish::Builtins.run('caller', ['abc'])
      assert_false result
    end
    assert_match(/invalid number/, output)
  end

  # Test caller with invalid option
  def test_caller_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('caller', ['-x'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test push_call_frame helper
  def test_push_call_frame
    Rubish::Builtins.push_call_frame(1, 'func1', 'file1.sh')
    Rubish::Builtins.push_call_frame(2, 'func2', 'file2.sh')

    assert_equal 2, Rubish::Builtins.call_stack.length
    assert_equal [1, 'func1', 'file1.sh'], Rubish::Builtins.call_stack[0]
    assert_equal [2, 'func2', 'file2.sh'], Rubish::Builtins.call_stack[1]
  end

  # Test pop_call_frame helper
  def test_pop_call_frame
    Rubish::Builtins.push_call_frame(1, 'func1', 'file1.sh')
    Rubish::Builtins.push_call_frame(2, 'func2', 'file2.sh')

    frame = Rubish::Builtins.pop_call_frame
    assert_equal [2, 'func2', 'file2.sh'], frame
    assert_equal 1, Rubish::Builtins.call_stack.length
  end

  # Test clear_call_stack helper
  def test_clear_call_stack
    Rubish::Builtins.push_call_frame(1, 'func1', 'file1.sh')
    Rubish::Builtins.push_call_frame(2, 'func2', 'file2.sh')

    Rubish::Builtins.clear_call_stack
    assert Rubish::Builtins.call_stack.empty?
  end

  # Test type identifies caller as builtin
  def test_type_identifies_caller_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['caller']) }
    assert_match(/caller is a shell builtin/, output)
  end

  # Test caller via REPL
  def test_caller_via_repl
    Rubish::Builtins.push_call_frame(10, 'myfunc', 'test.sh')

    output = capture_output { execute('caller') }
    assert_equal "10 myfunc test.sh\n", output
  end

  # Test deep call stack
  def test_deep_call_stack
    # Simulate a deep call stack
    10.times do |i|
      Rubish::Builtins.push_call_frame(i * 10, "func#{i}", "file#{i}.sh")
    end

    # Check frame 0 (most recent)
    output = capture_output { Rubish::Builtins.run('caller', ['0']) }
    assert_equal "90 func9 file9.sh\n", output

    # Check frame 9 (deepest)
    output = capture_output { Rubish::Builtins.run('caller', ['9']) }
    assert_equal "0 func0 file0.sh\n", output

    # Frame 10 should be out of range
    result = Rubish::Builtins.run('caller', ['10'])
    assert_false result
  end
end
