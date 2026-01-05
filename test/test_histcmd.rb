# frozen_string_literal: true

require_relative 'test_helper'

class TestHISTCMD < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_histcmd_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def command_number
    @repl.instance_variable_get(:@command_number)
  end

  # Basic HISTCMD functionality

  def test_histcmd_starts_at_one
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HISTCMD > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_histcmd_increments_with_commands
    output_file = File.join(@tempdir, 'output.txt')
    execute('echo first')
    execute('echo second')
    execute("echo $HISTCMD > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_histcmd_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HISTCMD} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_histcmd_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Command: $HISTCMD\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'Command: 1', content
  end

  def test_histcmd_multiple_on_same_line
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HISTCMD $HISTCMD > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal values[0], values[1], 'Multiple HISTCMD on same line should be equal'
  end

  # HISTCMD is read-only

  def test_histcmd_assignment_ignored
    execute('HISTCMD=100')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HISTCMD > #{output_file}")
    value = File.read(output_file).strip.to_i
    # HISTCMD should be 2 (assignment was command 1, echo is command 2)
    assert_equal 2, value, 'HISTCMD should not be affected by assignment'
  end

  def test_histcmd_not_stored_in_env
    assert_nil ENV['HISTCMD'], 'HISTCMD should not be stored in ENV'
    execute('echo $HISTCMD')
    assert_nil ENV['HISTCMD'], 'HISTCMD should still not be in ENV after access'
    execute('HISTCMD=123')
    assert_nil ENV['HISTCMD'], 'HISTCMD should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_histcmd_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HISTCMD:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_histcmd_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HISTCMD:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'HISTCMD should be considered set'
  end

  # String operations

  def test_histcmd_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#HISTCMD} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value  # '1'.length == 1
  end

  # Arithmetic

  def test_histcmd_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((HISTCMD + 10)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 11, value  # 1 + 10
  end

  # Edge cases

  def test_histcmd_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $HISTCMD) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Subshell should see the same HISTCMD as parent
    assert_equal 1, value
  end

  def test_histcmd_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    # Execute some commands in repl1
    repl1.send(:execute, 'echo one')
    repl1.send(:execute, 'echo two')
    repl1.send(:execute, 'echo three')

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $HISTCMD > #{output_file1}")
    repl2.send(:execute, "echo $HISTCMD > #{output_file2}")

    value1 = File.read(output_file1).strip.to_i
    value2 = File.read(output_file2).strip.to_i

    # repl1 has executed 4 commands, repl2 has executed 1
    assert_equal 4, value1
    assert_equal 1, value2
  end

  def test_histcmd_tracks_all_command_types
    output_file = File.join(@tempdir, 'output.txt')

    # Various command types
    execute('VAR=value')           # assignment
    execute('echo test')           # external command
    execute('true')                # builtin
    execute("echo $HISTCMD > #{output_file}")

    value = File.read(output_file).strip.to_i
    assert_equal 4, value
  end
end
