# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISHVERSION < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_version_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_VERSION functionality

  def test_rubish_version_returns_version_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_VERSION > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value
  end

  def test_rubish_version_matches_module_constant
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_VERSION > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0.0.1', value
  end

  def test_rubish_version_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSION} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value
  end

  def test_rubish_version_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Version: $RUBISH_VERSION\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Version: #{Rubish::VERSION}", content
  end

  def test_rubish_version_consistent_across_accesses
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_VERSION $RUBISH_VERSION > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal values[0], values[1], 'RUBISH_VERSION should be consistent'
  end

  # RUBISH_VERSION is read-only

  def test_rubish_version_assignment_ignored
    execute('RUBISH_VERSION=9.9.9')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_VERSION > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value, 'RUBISH_VERSION should not be affected by assignment'
  end

  def test_rubish_version_not_stored_in_env
    assert_nil ENV['RUBISH_VERSION'], 'RUBISH_VERSION should not be stored in ENV'
    execute('echo $RUBISH_VERSION')
    assert_nil ENV['RUBISH_VERSION'], 'RUBISH_VERSION should still not be in ENV after access'
    execute('RUBISH_VERSION=1.0.0')
    assert_nil ENV['RUBISH_VERSION'], 'RUBISH_VERSION should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_rubish_version_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSION:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value
  end

  def test_rubish_version_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSION:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RUBISH_VERSION should be considered set'
  end

  # String operations

  def test_rubish_version_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_VERSION} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Rubish::VERSION.length, value
  end

  def test_rubish_version_substring
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSION:0:1} > #{output_file}")
    value = File.read(output_file).strip
    # First character of version (e.g., '0' from '0.0.1')
    assert_equal Rubish::VERSION[0], value
  end

  def test_rubish_version_substring_from_middle
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSION:2:3} > #{output_file}")
    value = File.read(output_file).strip
    # Characters 2-4 of version (e.g., '0.1' from '0.0.1')
    assert_equal Rubish::VERSION[2, 3], value
  end

  # Edge cases

  def test_rubish_version_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo $RUBISH_VERSION) > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value
  end

  def test_rubish_version_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo $RUBISH_VERSION > #{output_file1}")
    repl2.send(:execute, "echo $RUBISH_VERSION > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    # Both should report the same version
    assert_equal Rubish::VERSION, value1
    assert_equal Rubish::VERSION, value2
    assert_equal value1, value2
  end

  # Comparison with BASH_VERSION (conceptual)

  def test_rubish_version_format
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH_VERSION > #{output_file}")
    value = File.read(output_file).strip
    # Version should be in semver-like format (x.y.z)
    assert_match(/^\d+\.\d+\.\d+/, value, 'RUBISH_VERSION should be in version format')
  end
end
