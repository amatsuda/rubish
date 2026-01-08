# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_VERSION < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_version_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_VERSION functionality

  def test_bash_version_returns_version_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_VERSION > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Rubish::VERSION, content, 'BASH_VERSION should return rubish version'
  end

  def test_bash_version_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSION} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal Rubish::VERSION, content
  end

  def test_bash_version_equals_rubish_version
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_VERSION $RUBISH_VERSION > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_VERSION should equal RUBISH_VERSION'
  end

  # BASH_VERSION is read-only

  def test_bash_version_assignment_ignored
    original = Rubish::VERSION
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_VERSION=9.9.9')
    execute("echo $BASH_VERSION > #{output_file}")
    content = File.read(output_file).strip
    assert_equal original, content, 'BASH_VERSION should not be assignable'
  end

  # Parameter expansion

  def test_bash_version_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSION:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_not_equal 'default', content, 'BASH_VERSION should not use default'
  end

  def test_bash_version_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSION:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASH_VERSION should be considered set'
  end

  def test_bash_version_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_VERSION} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert_equal Rubish::VERSION.length, content
  end

  # BASH_VERSION format

  def test_bash_version_format
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_VERSION > #{output_file}")
    content = File.read(output_file).strip
    # Version should match semver-like format (digits.digits.digits)
    assert_match(/^\d+\.\d+\.\d+/, content)
  end

  # BASH_VERSION in conditional

  def test_bash_version_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -n "$BASH_VERSION" ]; then echo set; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'set', content
  end

  # BASH_VERSION in double quotes

  def test_bash_version_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"version=$BASH_VERSION\" > #{output_file}")
    content = File.read(output_file).strip
    assert content.start_with?('version=')
    assert content.include?(Rubish::VERSION)
  end
end

class TestBASH_VERSINFO < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_versinfo_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_VERSINFO array functionality

  def test_bash_versinfo_element_0_is_major
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[0]} > #{output_file}")
    content = File.read(output_file).strip
    expected_major = Rubish::VERSION.split('.')[0]
    assert_equal expected_major, content
  end

  def test_bash_versinfo_element_1_is_minor
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[1]} > #{output_file}")
    content = File.read(output_file).strip
    expected_minor = Rubish::VERSION.split('.')[1]
    assert_equal expected_minor, content
  end

  def test_bash_versinfo_element_2_is_patch
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[2]} > #{output_file}")
    content = File.read(output_file).strip
    expected_patch = Rubish::VERSION.split('.')[2]
    assert_equal expected_patch, content
  end

  def test_bash_versinfo_element_4_is_release
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[4]} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'release', content
  end

  def test_bash_versinfo_element_5_is_machine_type
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[5]} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal RUBY_PLATFORM, content
  end

  # BASH_VERSINFO equals RUBISH_VERSINFO

  def test_bash_versinfo_equals_rubish_versinfo
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[0]} ${RUBISH_VERSINFO[0]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_VERSINFO[0] should equal RUBISH_VERSINFO[0]'
  end

  # BASH_VERSINFO all elements

  def test_bash_versinfo_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[@]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    # Element [3] is empty, so when split by whitespace, we get 5 parts
    assert_equal 5, parts.length, 'BASH_VERSINFO should have 5 non-empty elements when echoed'
  end

  def test_bash_versinfo_all_elements_star
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_VERSINFO[*]} > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    # Element [3] is empty, so when split by whitespace, we get 5 parts
    assert_equal 5, parts.length
  end

  # BASH_VERSINFO length

  def test_bash_versinfo_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_VERSINFO[@]} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert_equal 6, content
  end

  # BASH_VERSINFO indices

  def test_bash_versinfo_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!BASH_VERSINFO[@]} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '0 1 2 3 4 5', content
  end

  # BASH_VERSINFO is read-only

  def test_bash_versinfo_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_VERSINFO=test')
    execute("echo ${BASH_VERSINFO[0]} > #{output_file}")
    content = File.read(output_file).strip
    expected_major = Rubish::VERSION.split('.')[0]
    assert_equal expected_major, content, 'BASH_VERSINFO should not be assignable'
  end

  # BASH_VERSINFO in conditional

  def test_bash_versinfo_major_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ "${BASH_VERSINFO[0]}" -ge 0 ]; then echo valid; else echo invalid; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'valid', content
  end
end
