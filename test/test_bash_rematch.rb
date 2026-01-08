# frozen_string_literal: true

require_relative 'test_helper'

class TestBASH_REMATCH < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('bash_rematch_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def last_status
    @repl.instance_variable_get(:@last_status)
  end

  # BASH_REMATCH equals RUBISH_REMATCH

  def test_bash_rematch_equals_rubish_rematch
    execute('STR="hello123world"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    assert_equal 0, last_status

    # Both should return the same array
    bash_rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal '123', bash_rematch[0]
    assert_equal '123', bash_rematch[1]
  end

  def test_bash_rematch_element_access
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="test456end"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    execute("echo ${BASH_REMATCH[0]} ${BASH_REMATCH[1]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal '456 456', value
  end

  def test_bash_rematch_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="abc123xyz"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+) ]]')
    execute("echo ${BASH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal 'abc123xyz abc 123 xyz', value
  end

  def test_bash_rematch_star_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="abc123xyz"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+) ]]')
    execute("echo ${BASH_REMATCH[*]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal 'abc123xyz abc 123 xyz', value
  end

  def test_bash_rematch_length
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="a1b2c3"')
    execute('[[ $STR =~ ([a-z])([0-9])([a-z])([0-9]) ]]')
    execute("echo ${#BASH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip.to_i
    assert_equal 5, value  # Full match + 4 capture groups
  end

  def test_bash_rematch_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="a1b2"')
    execute('[[ $STR =~ (a)(1)(b)(2) ]]')
    execute("echo ${!BASH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal '0 1 2 3 4', value
  end

  # BASH_REMATCH is read-only

  def test_bash_rematch_assignment_ignored
    execute('STR="test123"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    execute('BASH_REMATCH=modified')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${BASH_REMATCH[0]} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '123', content, 'BASH_REMATCH should not be assignable'
  end

  def test_rubish_rematch_assignment_ignored
    execute('STR="test123"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    execute('RUBISH_REMATCH=modified')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_REMATCH[0]} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '123', content, 'RUBISH_REMATCH should not be assignable'
  end

  # BASH_REMATCH and RUBISH_REMATCH have same values

  def test_bash_rematch_matches_rubish_rematch_length
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="abc123xyz"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+) ]]')
    execute("echo ${#BASH_REMATCH[@]} ${#RUBISH_REMATCH[@]} > #{output_file}")

    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_REMATCH length should equal RUBISH_REMATCH length'
  end

  def test_bash_rematch_matches_rubish_rematch_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="hello42world"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+) ]]')
    execute("echo ${BASH_REMATCH[0]} ${RUBISH_REMATCH[0]} > #{output_file}")

    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_REMATCH[0] should equal RUBISH_REMATCH[0]'
  end

  def test_bash_rematch_matches_rubish_rematch_capture_group
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="test789end"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    execute("echo ${BASH_REMATCH[1]} ${RUBISH_REMATCH[1]} > #{output_file}")

    content = File.read(output_file).strip
    parts = content.split
    assert_equal parts[0], parts[1], 'BASH_REMATCH[1] should equal RUBISH_REMATCH[1]'
  end

  # Edge cases

  def test_bash_rematch_empty_when_no_match
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="hello"')
    execute('[[ $STR =~ [0-9]+ ]]')
    execute("echo x${BASH_REMATCH[0]}x > #{output_file}")

    content = File.read(output_file).strip
    assert_equal 'xx', content, 'BASH_REMATCH should be empty when no match'
  end

  def test_bash_rematch_with_capture_groups
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="abc123def456"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+)([0-9]+) ]]')
    execute("echo ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]} > #{output_file}")

    content = File.read(output_file).strip
    assert_equal 'abc 123 def 456', content
  end

  def test_bash_rematch_full_match
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="hello123world"')
    execute('[[ $STR =~ [a-z]+[0-9]+[a-z]+ ]]')
    execute("echo ${BASH_REMATCH[0]} > #{output_file}")

    content = File.read(output_file).strip
    assert_equal 'hello123world', content
  end

  def test_bash_rematch_with_empty_capture
    execute('STR="ab"')
    execute('[[ $STR =~ (a)(x?)(b) ]]')
    assert_equal 0, last_status

    # Access via BASH_REMATCH
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"${BASH_REMATCH[2]}\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal '', content, 'Empty capture group should be empty string'
  end
end
