# frozen_string_literal: true

require_relative 'test_helper'

class TestPPID < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_ppid_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic PPID functionality

  def test_ppid_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, "PPID should be a positive integer, got #{value}"
  end

  def test_ppid_matches_process_ppid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  def test_ppid_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  def test_ppid_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PPID} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  def test_ppid_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Parent: $PPID\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Parent: #{Process.ppid}", content
  end

  def test_ppid_is_constant
    # PPID should return the same value on multiple accesses
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PPID $PPID $PPID > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal 3, values.size
    assert values.uniq.size == 1, 'PPID should be constant across accesses'
  end

  # PPID is read-only

  def test_ppid_assignment_ignored
    original_ppid = Process.ppid
    execute('PPID=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $PPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal original_ppid, value, 'PPID should remain unchanged after assignment'
  end

  def test_ppid_not_stored_in_env
    assert_nil ENV['PPID'], 'PPID should not be stored in ENV'
    execute('echo $PPID')
    assert_nil ENV['PPID'], 'PPID should still not be in ENV after access'
    execute('PPID=123')
    assert_nil ENV['PPID'], 'PPID should not be in ENV after assignment attempt'
  end

  # Parameter expansion with PPID

  def test_ppid_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PPID:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  def test_ppid_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PPID:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'PPID should be considered set'
  end

  # Arithmetic with PPID

  def test_ppid_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((PPID + 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  def test_ppid_arithmetic_operations
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((PPID * 2 / 2)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.ppid, value
  end

  # Edge cases

  def test_ppid_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $PPID) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # In a subshell (forked), PPID is the parent process (the Ruby shell)
    assert_equal Process.pid, value
  end

  def test_ppid_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $PPID > #{output_file1}")
    repl2.send(:execute, "echo $PPID > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # Both should return the same PPID (parent of Ruby process)
    assert_equal value1, value2
    assert_equal Process.ppid, value1
  end
end
