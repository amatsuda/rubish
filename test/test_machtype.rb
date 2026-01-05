# frozen_string_literal: true

require_relative 'test_helper'

class TestMACHTYPE < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_machtype_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic MACHTYPE functionality

  def test_machtype_returns_platform_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $MACHTYPE > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value
  end

  def test_machtype_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${MACHTYPE} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value
  end

  def test_machtype_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Machine: $MACHTYPE\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Machine: #{RUBY_PLATFORM}", content
  end

  def test_machtype_consistent_across_accesses
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $MACHTYPE $MACHTYPE > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal values[0], values[1], 'MACHTYPE should be consistent'
  end

  # MACHTYPE is read-only

  def test_machtype_assignment_ignored
    execute('MACHTYPE=custom-platform')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $MACHTYPE > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value, 'MACHTYPE should not be affected by assignment'
  end

  def test_machtype_not_stored_in_env
    assert_nil ENV['MACHTYPE'], 'MACHTYPE should not be stored in ENV'
    execute('echo $MACHTYPE')
    assert_nil ENV['MACHTYPE'], 'MACHTYPE should still not be in ENV after access'
    execute('MACHTYPE=something')
    assert_nil ENV['MACHTYPE'], 'MACHTYPE should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_machtype_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${MACHTYPE:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value
  end

  def test_machtype_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${MACHTYPE:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'MACHTYPE should be considered set'
  end

  # String operations

  def test_machtype_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#MACHTYPE} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal RUBY_PLATFORM.length, value
  end

  def test_machtype_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${MACHTYPE:0:5} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM[0, 5], value
  end

  # Edge cases

  def test_machtype_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $MACHTYPE) > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value
  end

  def test_machtype_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $MACHTYPE > #{output_file1}")
    repl2.send(:execute, "echo $MACHTYPE > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    assert_equal RUBY_PLATFORM, value1
    assert_equal RUBY_PLATFORM, value2
  end

  # Relationship with OSTYPE and HOSTTYPE

  def test_machtype_equals_hosttype_dash_ostype
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $HOSTTYPE-$OSTYPE > #{output_file}")
    combined = File.read(output_file).strip

    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo $MACHTYPE > #{output_file2}")
    machtype = File.read(output_file2).strip

    # MACHTYPE should equal HOSTTYPE-OSTYPE (which is RUBY_PLATFORM)
    assert_equal machtype, combined
  end

  def test_machtype_contains_hosttype
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $MACHTYPE > #{output_file}")
    machtype = File.read(output_file).strip

    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo $HOSTTYPE > #{output_file2}")
    hosttype = File.read(output_file2).strip

    assert machtype.start_with?(hosttype), 'MACHTYPE should start with HOSTTYPE'
  end

  def test_machtype_contains_ostype
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $MACHTYPE > #{output_file}")
    machtype = File.read(output_file).strip

    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo $OSTYPE > #{output_file2}")
    ostype = File.read(output_file2).strip

    assert machtype.end_with?(ostype), 'MACHTYPE should end with OSTYPE'
  end
end
