# frozen_string_literal: true

require_relative 'test_helper'

class TestBASHPID < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bashpid_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASHPID functionality

  def test_bashpid_returns_current_pid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHPID > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Process.pid.to_s, content, 'BASHPID should return current process ID'
  end

  def test_bashpid_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHPID} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Process.pid.to_s, content
  end

  def test_bashpid_equals_rubishpid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHPID $RUBISHPID > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASHPID should equal RUBISHPID'
  end

  # BASHPID is read-only

  def test_bashpid_assignment_ignored
    original_pid = Process.pid.to_s
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASHPID=99999')
    execute("echo $BASHPID > #{output_file}")
    content = File.read(output_file).strip
    assert_equal original_pid, content, 'BASHPID should not be assignable'
  end

  # BASHPID is numeric

  def test_bashpid_is_numeric_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHPID > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/^\d+$/, content, 'BASHPID should be a numeric string')
  end

  def test_bashpid_is_positive
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHPID > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content > 0, 'BASHPID should be a positive number'
  end

  # Parameter expansion

  def test_bashpid_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHPID:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_not_equal 'default', content, 'BASHPID should not use default (always set)'
  end

  def test_bashpid_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASHPID:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASHPID should be considered set'
  end

  def test_bashpid_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASHPID} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 1, 'BASHPID length should be at least 1'
    # PID lengths are typically 1-7 digits
    assert content <= 7, 'BASHPID length should be at most 7 digits'
  end

  # BASHPID in conditional

  def test_bashpid_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -n "$BASHPID" ]; then echo set; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  def test_bashpid_numeric_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ "$BASHPID" -gt 0 ]; then echo positive; else echo zero; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'positive', content
  end

  # BASHPID in double quotes

  def test_bashpid_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"pid=$BASHPID\" > #{output_file}")
    content = File.read(output_file).strip
    assert content.start_with?('pid=')
    assert_match(/pid=\d+/, content)
  end

  # BASHPID arithmetic

  def test_bashpid_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((BASHPID + 0)) > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Process.pid.to_s, content
  end

  def test_bashpid_arithmetic_compare
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((BASHPID == RUBISHPID)) > #{output_file}")
    content = File.read(output_file).strip
    # rubish returns 'true' for comparison, bash returns '1'
    assert %w[1 true].include?(content), 'BASHPID == RUBISHPID should be true'
  end

  # BASHPID vs $$

  def test_bashpid_equals_dollar_dollar
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASHPID $$ > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    # In the main shell, BASHPID and $$ should be equal
    assert_equal parts[0], parts[1], 'In main shell, BASHPID should equal $$'
  end
end
