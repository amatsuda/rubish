# frozen_string_literal: true

require_relative 'test_helper'

class TestUIDEUID < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_uid_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic UID functionality

  def test_uid_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $UID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, "UID should be a non-negative integer, got #{value}"
  end

  def test_uid_matches_process_uid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $UID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.uid, value
  end

  def test_uid_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${UID} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.uid, value
  end

  def test_uid_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"User: $UID\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "User: #{Process.uid}", content
  end

  def test_uid_is_constant
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $UID $UID $UID > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal 3, values.size
    assert values.uniq.size == 1, 'UID should be constant across accesses'
  end

  # Basic EUID functionality

  def test_euid_returns_integer
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EUID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 0, "EUID should be a non-negative integer, got #{value}"
  end

  def test_euid_matches_process_euid
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EUID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.euid, value
  end

  def test_euid_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EUID} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.euid, value
  end

  def test_euid_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Effective: $EUID\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Effective: #{Process.euid}", content
  end

  # UID and EUID are read-only

  def test_uid_assignment_ignored
    original_uid = Process.uid
    execute('UID=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $UID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal original_uid, value, 'UID should remain unchanged after assignment'
  end

  def test_euid_assignment_ignored
    original_euid = Process.euid
    execute('EUID=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $EUID > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal original_euid, value, 'EUID should remain unchanged after assignment'
  end

  def test_uid_not_stored_in_env
    assert_nil ENV['UID'], 'UID should not be stored in ENV'
    execute('echo $UID')
    assert_nil ENV['UID'], 'UID should still not be in ENV after access'
    execute('UID=123')
    assert_nil ENV['UID'], 'UID should not be in ENV after assignment attempt'
  end

  def test_euid_not_stored_in_env
    assert_nil ENV['EUID'], 'EUID should not be stored in ENV'
    execute('echo $EUID')
    assert_nil ENV['EUID'], 'EUID should still not be in ENV after access'
    execute('EUID=123')
    assert_nil ENV['EUID'], 'EUID should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_uid_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${UID:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.uid, value
  end

  def test_uid_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${UID:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'UID should be considered set'
  end

  def test_euid_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EUID:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.euid, value
  end

  def test_euid_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${EUID:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'EUID should be considered set'
  end

  # Arithmetic

  def test_uid_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((UID + 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.uid, value
  end

  def test_euid_in_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((EUID + 0)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.euid, value
  end

  # Edge cases

  def test_uid_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $UID) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Subshell inherits UID from parent process
    assert value >= 0
  end

  def test_euid_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $EUID) > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Subshell inherits EUID from parent process
    assert value >= 0
  end

  def test_uid_and_euid_typically_equal
    # For normal users, UID and EUID are typically equal
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $UID $EUID > #{output_file}")
    values = File.read(output_file).strip.split
    # They should both be valid integers
    assert_equal Process.uid.to_s, values[0]
    assert_equal Process.euid.to_s, values[1]
  end

  def test_uid_euid_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $UID $EUID > #{output_file1}")
    repl2.send(:execute, "echo $UID $EUID > #{output_file2}")

    values1 = File.read(output_file1).strip.split
    values2 = File.read(output_file2).strip.split

    # Both should return the same values (from same process)
    assert_equal values1, values2
    assert_equal Process.uid.to_s, values1[0]
    assert_equal Process.euid.to_s, values1[1]
  end
end
