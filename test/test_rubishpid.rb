# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISHPID < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_rubishpid_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISHPID functionality

  def test_rubishpid_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISHPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value > 0, "RUBISHPID should be a positive integer, got #{value}"
  end

  def test_rubishpid_matches_process_pid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISHPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.pid, value
  end

  def test_rubishpid_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISHPID} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.pid, value
  end

  def test_rubishpid_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"PID: $RUBISHPID\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "PID: #{Process.pid}", content
  end

  def test_rubishpid_is_constant_in_main_shell
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISHPID $RUBISHPID $RUBISHPID > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal 3, values.size
    assert values.uniq.size == 1, 'RUBISHPID should be constant in main shell'
  end

  # RUBISHPID vs $$ - key difference is subshell behavior

  def test_rubishpid_differs_from_dollar_dollar_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    # In subshell, RUBISHPID should be the forked process PID
    # while $$ stays the same as parent
    execute("(echo $RUBISHPID) > #{output_file}")
    subshell_pid = File.read(output_file).strip.to_i
    # The subshell PID should be different from the main process
    assert subshell_pid != Process.pid, 'RUBISHPID should change in subshell'
  end

  def test_rubishpid_equals_ppid_of_subshell
    output_file = File.join(@tempdir, 'output.txt')
    # In subshell, PPID should equal the parent's RUBISHPID
    execute("(echo $PPID) > #{output_file}")
    subshell_ppid = File.read(output_file).strip.to_i
    assert_equal Process.pid, subshell_ppid, 'Subshell PPID should equal parent RUBISHPID'
  end

  # RUBISHPID is read-only

  def test_rubishpid_assignment_ignored
    original_pid = Process.pid
    execute('RUBISHPID=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISHPID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal original_pid, value, 'RUBISHPID should remain unchanged after assignment'
  end

  def test_rubishpid_not_stored_in_env
    assert_nil ENV['RUBISHPID'], 'RUBISHPID should not be stored in ENV'
    execute('echo $RUBISHPID')
    assert_nil ENV['RUBISHPID'], 'RUBISHPID should still not be in ENV after access'
    execute('RUBISHPID=123')
    assert_nil ENV['RUBISHPID'], 'RUBISHPID should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_rubishpid_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISHPID:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.pid, value
  end

  def test_rubishpid_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISHPID:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RUBISHPID should be considered set'
  end

  # String operations

  def test_rubishpid_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISHPID} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.pid.to_s.length, value
  end

  # Edge cases

  def test_rubishpid_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $RUBISHPID > #{output_file1}")
    repl2.send(:execute, "echo $RUBISHPID > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # Both should return the same PID (same Ruby process)
    assert_equal value1, value2
    assert_equal Process.pid, value1
  end
end
