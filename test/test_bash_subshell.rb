# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_SUBSHELL < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bash_subshell_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic BASH_SUBSHELL functionality

  def test_bash_subshell_equals_zero_at_top_level
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_SUBSHELL > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '0', content, 'BASH_SUBSHELL should be 0 at top level'
  end

  def test_bash_subshell_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_SUBSHELL} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '0', content
  end

  def test_bash_subshell_equals_rubish_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_SUBSHELL $RUBISH_SUBSHELL > #{output_file}")
    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_SUBSHELL should equal RUBISH_SUBSHELL'
  end

  # BASH_SUBSHELL is read-only

  def test_bash_subshell_assignment_ignored
    output_file = File.join(@tempdir, 'output.txt')
    execute('BASH_SUBSHELL=99')
    execute("echo $BASH_SUBSHELL > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '0', content, 'BASH_SUBSHELL should not be assignable'
  end

  # Parameter expansion

  def test_bash_subshell_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_SUBSHELL:-default} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '0', content, 'BASH_SUBSHELL should not use default (always set)'
  end

  def test_bash_subshell_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_SUBSHELL:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'BASH_SUBSHELL should be considered set'
  end

  def test_bash_subshell_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#BASH_SUBSHELL} > #{output_file}")
    content = File.read(output_file).strip.to_i
    assert content >= 1, 'BASH_SUBSHELL length should be at least 1'
  end

  # BASH_SUBSHELL in conditional

  def test_bash_subshell_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute('if [ "$BASH_SUBSHELL" -eq 0 ]; then echo top; else echo sub; fi > ' + output_file)
    content = File.read(output_file).strip
    assert_equal 'top', content
  end

  # BASH_SUBSHELL in double quotes

  def test_bash_subshell_in_double_quotes
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"level=$BASH_SUBSHELL\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'level=0', content
  end

  # BASH_SUBSHELL arithmetic

  def test_bash_subshell_arithmetic
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $((BASH_SUBSHELL + 1)) > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '1', content
  end

  # BASH_SUBSHELL returns string representation of integer

  def test_bash_subshell_is_numeric_string
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $BASH_SUBSHELL > #{output_file}")
    content = File.read(output_file).strip
    assert_match(/^\d+$/, content, 'BASH_SUBSHELL should be a numeric string')
  end
end
