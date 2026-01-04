# frozen_string_literal: true

require_relative 'test_helper'

class TestParamExpansion < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_param_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # ${var:-default} - use default if unset or null
  def test_default_when_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR:-default} > #{output_file}")
    assert_equal "default\n", File.read(output_file)
  end

  def test_default_when_null
    ENV['NULL_VAR'] = ''
    execute("echo ${NULL_VAR:-default} > #{output_file}")
    assert_equal "default\n", File.read(output_file)
  end

  def test_default_when_set
    ENV['SET_VAR'] = 'value'
    execute("echo ${SET_VAR:-default} > #{output_file}")
    assert_equal "value\n", File.read(output_file)
  end

  # ${var-default} - use default only if unset
  def test_unset_only_default_when_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR-default} > #{output_file}")
    assert_equal "default\n", File.read(output_file)
  end

  def test_unset_only_default_when_null
    ENV['NULL_VAR'] = ''
    execute("echo ${NULL_VAR-default} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${var:=default} - assign default if unset or null
  def test_assign_default_when_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR:=assigned} > #{output_file}")
    assert_equal "assigned\n", File.read(output_file)
    assert_equal 'assigned', ENV['UNSET_VAR']
  end

  # ${var:+value} - use value if set and non-null
  def test_alternate_when_set
    ENV['SET_VAR'] = 'exists'
    execute("echo ${SET_VAR:+alternate} > #{output_file}")
    assert_equal "alternate\n", File.read(output_file)
  end

  def test_alternate_when_unset
    ENV.delete('UNSET_VAR')
    execute("echo ${UNSET_VAR:+alternate} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end

  # ${#var} - length
  def test_length
    ENV['LEN_VAR'] = 'hello'
    execute("echo ${#LEN_VAR} > #{output_file}")
    assert_equal "5\n", File.read(output_file)
  end

  # ${var:offset} and ${var:offset:length} - substring
  def test_substring_offset
    ENV['STR_VAR'] = 'hello world'
    execute("echo ${STR_VAR:6} > #{output_file}")
    assert_equal "world\n", File.read(output_file)
  end

  def test_substring_offset_length
    ENV['STR_VAR'] = 'hello world'
    execute("echo ${STR_VAR:0:5} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # ${var#pattern} - remove shortest prefix
  def test_remove_shortest_prefix
    ENV['PATH_VAR'] = '/usr/local/bin'
    execute("echo ${PATH_VAR#*/} > #{output_file}")
    assert_equal "usr/local/bin\n", File.read(output_file)
  end

  # ${var##pattern} - remove longest prefix
  def test_remove_longest_prefix
    ENV['PATH_VAR'] = '/usr/local/bin'
    execute("echo ${PATH_VAR##*/} > #{output_file}")
    assert_equal "bin\n", File.read(output_file)
  end

  # ${var%pattern} - remove shortest suffix
  def test_remove_shortest_suffix
    ENV['FILE_VAR'] = 'file.tar.gz'
    execute("echo ${FILE_VAR%.*} > #{output_file}")
    assert_equal "file.tar\n", File.read(output_file)
  end

  # ${var%%pattern} - remove longest suffix
  def test_remove_longest_suffix
    ENV['FILE_VAR'] = 'file.tar.gz'
    execute("echo ${FILE_VAR%%.*} > #{output_file}")
    assert_equal "file\n", File.read(output_file)
  end

  # ${var/pattern/replacement} - replace first
  def test_replace_first
    ENV['REP_VAR'] = 'hello hello'
    execute("echo ${REP_VAR/hello/hi} > #{output_file}")
    assert_equal "hi hello\n", File.read(output_file)
  end

  # ${var//pattern/replacement} - replace all
  def test_replace_all
    ENV['REP_VAR'] = 'hello hello'
    execute("echo ${REP_VAR//hello/hi} > #{output_file}")
    assert_equal "hi hi\n", File.read(output_file)
  end

  # ${var^} - uppercase first
  def test_uppercase_first
    ENV['CASE_VAR'] = 'hello'
    execute("echo ${CASE_VAR^} > #{output_file}")
    assert_equal "Hello\n", File.read(output_file)
  end

  # ${var^^} - uppercase all
  def test_uppercase_all
    ENV['CASE_VAR'] = 'hello'
    execute("echo ${CASE_VAR^^} > #{output_file}")
    assert_equal "HELLO\n", File.read(output_file)
  end

  # ${var,} - lowercase first
  def test_lowercase_first
    ENV['CASE_VAR'] = 'HELLO'
    execute("echo ${CASE_VAR,} > #{output_file}")
    assert_equal "hELLO\n", File.read(output_file)
  end

  # ${var,,} - lowercase all
  def test_lowercase_all
    ENV['CASE_VAR'] = 'HELLO'
    execute("echo ${CASE_VAR,,} > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # ${!var} - indirect expansion
  def test_indirect_expansion
    ENV['PTR_VAR'] = 'TARGET_VAR'
    ENV['TARGET_VAR'] = 'indirect value'
    execute("echo ${!PTR_VAR} > #{output_file}")
    assert_equal "indirect value\n", File.read(output_file)
  end

  def test_indirect_expansion_unset
    ENV['PTR_VAR'] = 'NONEXISTENT'
    ENV.delete('NONEXISTENT')
    execute("echo ${!PTR_VAR} > #{output_file}")
    assert_equal "\n", File.read(output_file)
  end
end
