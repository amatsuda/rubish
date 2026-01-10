# frozen_string_literal: true

require_relative 'test_helper'

class TestArithFor < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_arith_for_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def execute(line)
    @repl.send(:execute, line)
    @repl.instance_variable_get(:@last_status)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Basic C-style for loop
  def test_basic_for_loop
    execute("for ((i=1; i<=3; i++)); do echo $i; done > #{output_file}")
    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  def test_sum_loop
    execute("sum=0; for ((i=1; i<=5; i++)); do (( sum += i )); done; echo $sum > #{output_file}")
    assert_equal "15\n", File.read(output_file)
  end

  def test_countdown
    execute("for ((i=3; i>0; i--)); do echo $i; done > #{output_file}")
    assert_equal "3\n2\n1\n", File.read(output_file)
  end

  def test_decrement
    execute("for ((i=5; i>=1; i--)); do echo $i; done > #{output_file}")
    assert_equal "5\n4\n3\n2\n1\n", File.read(output_file)
  end

  def test_step_by_two
    execute("for ((i=0; i<10; i+=2)); do echo $i; done > #{output_file}")
    assert_equal "0\n2\n4\n6\n8\n", File.read(output_file)
  end

  def test_variable_limit
    execute("n=4; for ((i=1; i<=n; i++)); do echo $i; done > #{output_file}")
    assert_equal "1\n2\n3\n4\n", File.read(output_file)
  end

  def test_zero_iterations
    execute("for ((i=5; i<3; i++)); do echo $i; done > #{output_file}")
    assert_equal '', File.read(output_file)
  end

  def test_single_iteration
    execute("for ((i=1; i<=1; i++)); do echo $i; done > #{output_file}")
    assert_equal "1\n", File.read(output_file)
  end

  # Test with pre-increment
  def test_pre_increment
    execute("for ((i=0; i<3; ++i)); do echo $i; done > #{output_file}")
    assert_equal "0\n1\n2\n", File.read(output_file)
  end

  # Test with pre-decrement
  def test_pre_decrement
    execute("for ((i=3; i>0; --i)); do echo $i; done > #{output_file}")
    assert_equal "3\n2\n1\n", File.read(output_file)
  end

  # Test with multiplication
  def test_multiply_step
    execute("for ((i=1; i<=32; i*=2)); do echo $i; done > #{output_file}")
    assert_equal "1\n2\n4\n8\n16\n32\n", File.read(output_file)
  end

  # Test multiple initializations
  def test_multiple_init
    execute("for ((i=0, j=10; i<3; i++, j--)); do echo \"$i $j\"; done > #{output_file}")
    assert_equal "0 10\n1 9\n2 8\n", File.read(output_file)
  end

  # Test empty init (infinite loop with break)
  def test_empty_init
    execute("i=1; for ((; i<=3; i++)); do echo $i; done > #{output_file}")
    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  # Test empty update
  def test_empty_update
    execute("for ((i=1; i<=3; )); do echo $i; (( i++ )); done > #{output_file}")
    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  # Test with break
  def test_break_in_loop
    execute("for ((i=1; i<=10; i++)); do if (( i > 3 )); then break; fi; echo $i; done > #{output_file}")
    assert_equal "1\n2\n3\n", File.read(output_file)
  end

  # Test with continue
  def test_continue_in_loop
    execute("for ((i=1; i<=5; i++)); do if (( i == 3 )); then continue; fi; echo $i; done > #{output_file}")
    assert_equal "1\n2\n4\n5\n", File.read(output_file)
  end

  # Test exit status (last command in loop)
  def test_exit_status
    status = execute('for ((i=0; i<3; i++)); do true; done')
    assert_equal 0, status
  end

  # Test nested for loops
  def test_nested_loops
    execute("for ((i=0; i<2; i++)); do for ((j=0; j<2; j++)); do echo \"$i,$j\"; done; done > #{output_file}")
    assert_equal "0,0\n0,1\n1,0\n1,1\n", File.read(output_file)
  end

  # Test complex condition
  def test_complex_condition
    execute("for ((i=0; i<10 && i%3!=0 || i==0; i++)); do echo $i; done > #{output_file}")
    # i=0: i<10 && 0!=0 (false) || true = true
    # i=1: i<10 && 1!=0 (true) = true
    # i=2: i<10 && 2!=0 (true) = true
    # i=3: i<10 && 0!=0 (false) || false = false -> stop
    assert_equal "0\n1\n2\n", File.read(output_file)
  end

  # Test variable is set after loop
  def test_variable_persists
    execute("for ((i=1; i<=3; i++)); do :; done; echo $i > #{output_file}")
    assert_equal "4\n", File.read(output_file)  # i is incremented one more time before condition fails
  end

  # Test with string output
  def test_build_string
    execute("result=\"\"; for ((i=0; i<3; i++)); do result=\"${result}${i}\"; done; echo $result > #{output_file}")
    assert_equal "012\n", File.read(output_file)
  end
end
