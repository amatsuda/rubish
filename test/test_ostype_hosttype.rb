# frozen_string_literal: true

require_relative 'test_helper'

class TestOSTYPEHOSTTYPE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_ostype_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # OSTYPE tests

  def test_ostype_returns_os_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $OSTYPE > #{output_file}")
    value = File.read(output_file).strip
    # OSTYPE should be the OS part of RUBY_PLATFORM
    expected = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    assert_equal expected, value
  end

  def test_ostype_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${OSTYPE} > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    assert_equal expected, value
  end

  def test_ostype_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"OS: $OSTYPE\" > #{output_file}")
    content = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    assert_equal "OS: #{expected}", content
  end

  def test_ostype_assignment_ignored
    execute('OSTYPE=windows')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $OSTYPE > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    assert_equal expected, value, 'OSTYPE should not be affected by assignment'
  end

  def test_ostype_not_stored_in_env
    assert_nil ENV['OSTYPE'], 'OSTYPE should not be stored in ENV'
    execute('echo $OSTYPE')
    assert_nil ENV['OSTYPE'], 'OSTYPE should still not be in ENV after access'
  end

  def test_ostype_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${OSTYPE:-default} > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    assert_equal expected, value
  end

  def test_ostype_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${OSTYPE:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'OSTYPE should be considered set'
  end

  def test_ostype_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#OSTYPE} > #{output_file}")
    value = File.read(output_file).strip.to_i
    expected = (RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM).length
    assert_equal expected, value
  end

  def test_ostype_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${OSTYPE:0:3} > #{output_file}")
    value = File.read(output_file).strip
    expected = (RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM)[0, 3]
    assert_equal expected, value
  end

  # HOSTTYPE tests

  def test_hosttype_returns_arch_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTTYPE > #{output_file}")
    value = File.read(output_file).strip
    # HOSTTYPE should be the architecture part of RUBY_PLATFORM
    expected = RUBY_PLATFORM.split('-').first
    assert_equal expected, value
  end

  def test_hosttype_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTTYPE} > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-').first
    assert_equal expected, value
  end

  def test_hosttype_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Host: $HOSTTYPE\" > #{output_file}")
    content = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-').first
    assert_equal "Host: #{expected}", content
  end

  def test_hosttype_assignment_ignored
    execute('HOSTTYPE=i386')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTTYPE > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-').first
    assert_equal expected, value, 'HOSTTYPE should not be affected by assignment'
  end

  def test_hosttype_not_stored_in_env
    assert_nil ENV['HOSTTYPE'], 'HOSTTYPE should not be stored in ENV'
    execute('echo $HOSTTYPE')
    assert_nil ENV['HOSTTYPE'], 'HOSTTYPE should still not be in ENV after access'
  end

  def test_hosttype_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTTYPE:-default} > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-').first
    assert_equal expected, value
  end

  def test_hosttype_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTTYPE:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'HOSTTYPE should be considered set'
  end

  def test_hosttype_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#HOSTTYPE} > #{output_file}")
    value = File.read(output_file).strip.to_i
    expected = RUBY_PLATFORM.split('-').first.length
    assert_equal expected, value
  end

  def test_hosttype_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${HOSTTYPE:0:3} > #{output_file}")
    value = File.read(output_file).strip
    expected = RUBY_PLATFORM.split('-').first[0, 3]
    assert_equal expected, value
  end

  # Combined tests

  def test_ostype_and_hosttype_together
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTTYPE-$OSTYPE > #{output_file}")
    value = File.read(output_file).strip
    # Should reconstruct something similar to RUBY_PLATFORM
    assert_equal RUBY_PLATFORM, value
  end

  def test_ostype_and_hosttype_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $OSTYPE $HOSTTYPE) > #{output_file}")
    values = File.read(output_file).strip.split
    expected_os = RUBY_PLATFORM.split('-', 2)[1] || RUBY_PLATFORM
    expected_host = RUBY_PLATFORM.split('-').first
    assert_equal expected_os, values[0]
    assert_equal expected_host, values[1]
  end

  def test_ostype_hosttype_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $OSTYPE $HOSTTYPE > #{output_file1}")
    repl2.send(:execute, "echo $OSTYPE $HOSTTYPE > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    assert_equal value1, value2
  end
end
