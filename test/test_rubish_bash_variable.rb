# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_Variable < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_variable_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic RUBISH variable functionality

  def test_rubish_variable_is_set
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH > #{output_file}")
    content = File.read(output_file).strip
    refute_empty content, 'RUBISH should be set'
  end

  def test_rubish_variable_is_path
    # Skip when running under rake/test loader (RUBISH returns $PROGRAM_NAME which is the test loader)
    omit 'RUBISH reflects $PROGRAM_NAME which is test loader when running tests' unless $PROGRAM_NAME.include?('rubish')

    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH > #{output_file}")
    content = File.read(output_file).strip
    # Should contain 'rubish' somewhere in the path
    assert_match(/rubish/, content, 'RUBISH should contain rubish in path')
  end

  def test_rubish_variable_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH} > #{output_file}")
    content = File.read(output_file).strip
    refute_empty content, 'RUBISH braced expansion should work'
  end

  # BASH variable as alias

  def test_bash_variable_equals_rubish
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH $RUBISH > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal 2, parts.length
    assert_equal parts[0], parts[1], 'BASH should equal RUBISH'
  end

  def test_bash_variable_is_set
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH > #{output_file}")
    content = File.read(output_file).strip
    refute_empty content, 'BASH should be set'
  end

  def test_bash_variable_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH} > #{output_file}")
    content = File.read(output_file).strip
    refute_empty content, 'BASH braced expansion should work'
  end

  # Read-only behavior

  def test_rubish_variable_is_read_only
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $RUBISH > #{output_file}")
    original = File.read(output_file).strip

    execute('RUBISH=/some/other/path')
    execute("echo $RUBISH > #{output_file}")
    content = File.read(output_file).strip

    assert_equal original, content, 'RUBISH should be read-only'
  end

  def test_bash_variable_is_read_only
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH > #{output_file}")
    original = File.read(output_file).strip

    execute('BASH=/some/other/path')
    execute("echo $BASH > #{output_file}")
    content = File.read(output_file).strip

    assert_equal original, content, 'BASH should be read-only'
  end

  # Parameter expansion

  def test_rubish_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH:-default} > #{output_file}")
    content = File.read(output_file).strip
    refute_equal 'default', content, 'RUBISH should not use default'
  end

  def test_rubish_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'RUBISH alternate expansion should return "set"'
  end

  def test_rubish_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content > 0, 'RUBISH length should be greater than 0'
  end

  def test_bash_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content > 0, 'BASH length should be greater than 0'
  end

  # Double quotes

  def test_rubish_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"shell=$RUBISH\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/^shell=/, content, 'RUBISH should expand in double quotes')
    refute_equal 'shell=', content, 'RUBISH should have a value'
  end

  def test_bash_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"shell=$BASH\" > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/^shell=/, content, 'BASH should expand in double quotes')
    refute_equal 'shell=', content, 'BASH should have a value'
  end

  # Conditional tests

  def test_rubish_in_conditional_not_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -n "$RUBISH" ]; then echo notempty; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'notempty', content, 'RUBISH should not be empty'
  end

  def test_bash_in_conditional_not_empty
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ -n "$BASH" ]; then echo notempty; else echo empty; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'notempty', content, 'BASH should not be empty'
  end
end
