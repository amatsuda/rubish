# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISHVERSINFO < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_versinfo_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH_VERSINFO array access

  def test_versinfo_major_version
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[0]} > #{output_file}")
    value = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[0]
    assert_equal expected, value
  end

  def test_versinfo_minor_version
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[1]} > #{output_file}")
    value = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[1]
    assert_equal expected, value
  end

  def test_versinfo_patch_level
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[2]} > #{output_file}")
    value = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[2]
    assert_equal expected, value
  end

  def test_versinfo_extra_version
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_VERSINFO[3]}x\" > #{output_file}")
    value = File.read(output_file).strip
    # Extra version is empty by default
    assert_equal 'xx', value
  end

  def test_versinfo_release_status
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[4]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'release', value
  end

  def test_versinfo_machine_type
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[5]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, value
  end

  # Array expansion

  def test_versinfo_all_elements_at
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[@]} > #{output_file}")
    value = File.read(output_file).strip
    parts = Rubish::VERSION.split('.')
    expected_parts = [parts[0], parts[1], parts[2], '', 'release', RUBY_PLATFORM]
    assert_equal expected_parts.join(' '), value
  end

  def test_versinfo_all_elements_star
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[*]} > #{output_file}")
    value = File.read(output_file).strip
    parts = Rubish::VERSION.split('.')
    expected_parts = [parts[0], parts[1], parts[2], '', 'release', RUBY_PLATFORM]
    assert_equal expected_parts.join(' '), value
  end

  def test_versinfo_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_VERSINFO[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 6, value
  end

  def test_versinfo_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!RUBISH_VERSINFO[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 2 3 4 5', value
  end

  # Read-only behavior

  def test_versinfo_assignment_ignored
    execute('RUBISH_VERSINFO=something')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[0]} > #{output_file}")
    value = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[0]
    assert_equal expected, value, 'RUBISH_VERSINFO should not be affected by assignment'
  end

  def test_versinfo_not_stored_in_env
    assert_nil ENV['RUBISH_VERSINFO'], 'RUBISH_VERSINFO should not be stored in ENV'
    execute('echo ${RUBISH_VERSINFO[0]}')
    assert_nil ENV['RUBISH_VERSINFO'], 'RUBISH_VERSINFO should still not be in ENV after access'
  end

  # Edge cases

  def test_versinfo_out_of_bounds_returns_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_VERSINFO[99]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_versinfo_negative_index
    output_file = File.join(@tempdir, 'output.txt')
    # Ruby arrays support negative indices
    execute("echo ${RUBISH_VERSINFO[-1]} > #{output_file}")
    value = File.read(output_file).strip
    # Last element is RUBY_PLATFORM
    assert_equal RUBY_PLATFORM, value
  end

  def test_versinfo_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo ${RUBISH_VERSINFO[0]}) > #{output_file}")
    value = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[0]
    assert_equal expected, value
  end

  def test_versinfo_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo ${RUBISH_VERSINFO[0]} > #{output_file1}")
    repl2.send(:execute, "echo ${RUBISH_VERSINFO[0]} > #{output_file2}")

    value1 = File.read(output_file1).strip
    value2 = File.read(output_file2).strip

    assert_equal value1, value2
  end

  # Comparison with version string

  def test_versinfo_matches_rubish_version
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_VERSINFO[0]}.${RUBISH_VERSINFO[1]}.${RUBISH_VERSINFO[2]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal Rubish::VERSION, value
  end

  def test_versinfo_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Major: ${RUBISH_VERSINFO[0]}\" > #{output_file}")
    content = File.read(output_file).strip
    expected = Rubish::VERSION.split('.')[0]
    assert_equal "Major: #{expected}", content
  end
end
