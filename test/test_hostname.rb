# frozen_string_literal: true

require_relative 'test_helper'

class TestHOSTNAME < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_hostname_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic HOSTNAME functionality

  def test_hostname_returns_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTNAME > #{output_file}")
    value = File.read(output_file).strip
    assert value.length > 0, 'HOSTNAME should return a non-empty string'
  end

  def test_hostname_matches_socket_gethostname
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTNAME > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Socket.gethostname, value
  end

  def test_hostname_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTNAME} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Socket.gethostname, value
  end

  def test_hostname_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Host: $HOSTNAME\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Host: #{Socket.gethostname}", content
  end

  def test_hostname_is_constant
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTNAME $HOSTNAME $HOSTNAME > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal 3, values.size
    assert values.uniq.size == 1, 'HOSTNAME should be constant across accesses'
  end

  # HOSTNAME is read-only

  def test_hostname_assignment_ignored
    original_hostname = Socket.gethostname
    execute('HOSTNAME=fakehostname')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTNAME > #{output_file}")
    value = File.read(output_file).strip
    assert_equal original_hostname, value, 'HOSTNAME should remain unchanged after assignment'
  end

  def test_hostname_not_stored_in_env
    assert_nil ENV['HOSTNAME'], 'HOSTNAME should not be stored in ENV'
    execute('echo $HOSTNAME')
    assert_nil ENV['HOSTNAME'], 'HOSTNAME should still not be in ENV after access'
    execute('HOSTNAME=fake')
    assert_nil ENV['HOSTNAME'], 'HOSTNAME should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_hostname_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTNAME:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Socket.gethostname, value
  end

  def test_hostname_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTNAME:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'HOSTNAME should be considered set'
  end

  # String operations

  def test_hostname_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#HOSTNAME} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Socket.gethostname.length, value
  end

  def test_hostname_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTNAME:0:3} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Socket.gethostname[0, 3], value
  end

  # Edge cases

  def test_hostname_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $HOSTNAME) > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Socket.gethostname, value
  end

  def test_hostname_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $HOSTNAME > #{output_file1}")
    repl2.send(:execute, "echo $HOSTNAME > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    # Both should return the same hostname
    assert_equal value1, value2
    assert_equal Socket.gethostname, value1
  end

  def test_hostname_in_prompt
    # HOSTNAME is often used in PS1
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"user@$HOSTNAME\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "user@#{Socket.gethostname}", content
  end
end
