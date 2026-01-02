# frozen_string_literal: true

require_relative 'test_helper'

class TestParameterExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_param_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    # Restore environment
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # ${var:-default} - use default if unset or null
  def test_default_value_unset
    ENV.delete('TESTVAR')
    execute("echo ${TESTVAR:-default} > #{output_file}")
    assert_equal "default\n", File.read(output_file)
  end

  def test_default_value_empty
    ENV['TESTVAR'] = ''
    execute("echo ${TESTVAR:-default} > #{output_file}")
    assert_equal "default\n", File.read(output_file)
  end

  def test_default_value_set
    ENV['TESTVAR'] = 'value'
    execute("echo ${TESTVAR:-default} > #{output_file}")
    assert_equal "value\n", File.read(output_file)
  end

  # ${var:=default} - assign default if unset or null
  def test_assign_default_unset
    ENV.delete('TESTVAR')
    execute("echo ${TESTVAR:=assigned} > #{output_file}")
    assert_equal "assigned\n", File.read(output_file)
  end

  # ${var:+value} - use value if set and non-null
  def test_alternate_value_unset
    ENV.delete('TESTVAR')
    execute("echo ${TESTVAR:+alternate} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  def test_alternate_value_set
    ENV['TESTVAR'] = 'something'
    execute("echo ${TESTVAR:+alternate} > #{output_file}")
    assert_equal "alternate\n", File.read(output_file)
  end

  def test_alternate_value_empty
    ENV['TESTVAR'] = ''
    execute("echo ${TESTVAR:+alternate} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${#var} - length of value
  def test_length
    ENV['TESTVAR'] = 'hello'
    execute("echo ${#TESTVAR} > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  def test_length_empty
    ENV['TESTVAR'] = ''
    execute("echo ${#TESTVAR} > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  def test_length_unset
    ENV.delete('TESTVAR')
    execute("echo ${#TESTVAR} > #{output_file}")
    assert_equal "0\n", File.read(output_file)
  end

  # ${var#pattern} - remove shortest prefix
  def test_prefix_shortest
    ENV['TESTVAR'] = '/usr/local/bin'
    execute("echo ${TESTVAR#*/} > #{output_file}")
    assert_equal "usr/local/bin\n", File.read(output_file)
  end

  # ${var##pattern} - remove longest prefix
  def test_prefix_longest
    ENV['TESTVAR'] = '/usr/local/bin'
    execute("echo ${TESTVAR##*/} > #{output_file}")
    assert_equal "bin\n", File.read(output_file)
  end

  # ${var%pattern} - remove shortest suffix
  def test_suffix_shortest
    ENV['TESTVAR'] = 'test.tar.gz'
    execute("echo ${TESTVAR%.*} > #{output_file}")
    assert_equal "test.tar\n", File.read(output_file)
  end

  # ${var%%pattern} - remove longest suffix
  def test_suffix_longest
    ENV['TESTVAR'] = 'test.tar.gz'
    execute("echo ${TESTVAR%%.*} > #{output_file}")
    assert_equal "test\n", File.read(output_file)
  end

  def test_suffix_path_shortest
    ENV['TESTVAR'] = '/path/to/file.txt'
    execute("echo ${TESTVAR%/*} > #{output_file}")
    assert_equal "/path/to\n", File.read(output_file)
  end

  def test_suffix_path_longest
    ENV['TESTVAR'] = '/path/to/file.txt'
    execute("echo ${TESTVAR%%/*} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var:offset} - substring from offset
  def test_substring_offset
    ENV['TESTVAR'] = 'hello world'
    execute("echo ${TESTVAR:6} > #{output_file}")
    assert_equal "world\n", File.read(output_file)
  end

  # ${var:offset:length} - substring with length
  def test_substring_offset_length
    ENV['TESTVAR'] = 'hello world'
    execute("echo ${TESTVAR:0:5} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_substring_middle
    ENV['TESTVAR'] = 'hello'
    execute("echo ${TESTVAR:1:3} > #{output_file}")
    assert_equal "ell\n", File.read(output_file)
  end

  # Simple ${VAR} still works
  def test_simple_braced_var
    ENV['TESTVAR'] = 'simple'
    execute("echo ${TESTVAR} > #{output_file}")
    assert_equal "simple\n", File.read(output_file)
  end

  # Combined with other expansions
  def test_in_string
    ENV['NAME'] = 'world'
    execute("echo \"Hello, ${NAME:-nobody}!\" > #{output_file}")
    assert_equal "Hello, world!\n", File.read(output_file)
  end

  def test_multiple_expansions
    ENV['A'] = 'foo'
    ENV['B'] = 'bar'
    execute("echo ${A:-x}${B:-y} > #{output_file}")
    assert_equal "foobar\n", File.read(output_file)
  end

  # Common use cases
  def test_filename_without_extension
    ENV['FILE'] = 'document.pdf'
    execute("echo ${FILE%.*} > #{output_file}")
    assert_equal "document\n", File.read(output_file)
  end

  def test_extension_only
    ENV['FILE'] = 'document.pdf'
    execute("echo ${FILE##*.} > #{output_file}")
    assert_equal "pdf\n", File.read(output_file)
  end

  def test_basename
    ENV['PATH_VAR'] = '/home/user/documents/file.txt'
    execute("echo ${PATH_VAR##*/} > #{output_file}")
    assert_equal "file.txt\n", File.read(output_file)
  end

  def test_dirname
    ENV['PATH_VAR'] = '/home/user/documents/file.txt'
    execute("echo ${PATH_VAR%/*} > #{output_file}")
    assert_equal "/home/user/documents\n", File.read(output_file)
  end
end
