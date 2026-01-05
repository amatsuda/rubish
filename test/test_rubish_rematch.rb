# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_REMATCH < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_rematch_test')
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

  # Basic RUBISH_REMATCH functionality

  def test_rubish_rematch_set_on_match
    execute('STR="hello123world"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    assert_equal 0, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal '123', rematch[0]  # Full match
    assert_equal '123', rematch[1]  # First capture group
  end

  def test_rubish_rematch_full_match_at_index_0
    execute('STR="abc123def"')
    execute('[[ $STR =~ [0-9]+ ]]')

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal '123', rematch[0]
  end

  def test_rubish_rematch_capture_groups
    execute('STR="abc123xyz"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+) ]]')
    assert_equal 0, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal 'abc123xyz', rematch[0]  # Full match
    assert_equal 'abc', rematch[1]        # First group
    assert_equal '123', rematch[2]        # Second group
    assert_equal 'xyz', rematch[3]        # Third group
  end

  def test_rubish_rematch_empty_on_no_match
    execute('STR="hello"')
    execute('[[ $STR =~ [0-9]+ ]]')
    assert_equal 1, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal [], rematch
  end

  def test_rubish_rematch_accessible_via_variable_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="test456end"')
    execute('[[ $STR =~ ([0-9]+) ]]')
    execute("echo ${RUBISH_REMATCH[0]} ${RUBISH_REMATCH[1]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal '456 456', value
  end

  def test_rubish_rematch_all_elements
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="abc123xyz"')
    execute('[[ $STR =~ ([a-z]+)([0-9]+)([a-z]+) ]]')
    execute("echo ${RUBISH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal 'abc123xyz abc 123 xyz', value
  end

  def test_rubish_rematch_length
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="a1b2c3"')
    execute('[[ $STR =~ ([a-z])([0-9])([a-z])([0-9]) ]]')
    execute("echo ${#RUBISH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip.to_i
    assert_equal 5, value  # Full match + 4 capture groups
  end

  def test_rubish_rematch_persists_until_next_match
    execute('STR1="hello123"')
    execute('[[ $STR1 =~ ([0-9]+) ]]')

    rematch1 = Rubish::Builtins.get_array('RUBISH_REMATCH').dup

    # Run a non-matching command
    execute('echo test')

    # RUBISH_REMATCH should still have the old value
    rematch2 = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal rematch1, rematch2
  end

  def test_rubish_rematch_updated_on_new_match
    execute('STR1="abc123"')
    execute('[[ $STR1 =~ ([0-9]+) ]]')

    execute('STR2="xyz789"')
    execute('[[ $STR2 =~ ([0-9]+) ]]')

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal '789', rematch[0]
    assert_equal '789', rematch[1]
  end

  def test_rubish_rematch_cleared_on_failed_match
    execute('STR1="abc123"')
    execute('[[ $STR1 =~ ([0-9]+) ]]')
    assert_equal 0, last_status

    execute('STR2="nodigits"')
    execute('[[ $STR2 =~ ([0-9]+) ]]')
    assert_equal 1, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal [], rematch
  end

  # Edge cases

  def test_rubish_rematch_with_empty_capture_group
    execute('STR="ab"')
    execute('[[ $STR =~ (a)(x?)(b) ]]')
    assert_equal 0, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal 'ab', rematch[0]
    assert_equal 'a', rematch[1]
    assert_equal '', rematch[2]  # Empty match for x?
    assert_equal 'b', rematch[3]
  end

  def test_rubish_rematch_with_nested_groups
    execute('STR="abc123"')
    execute('[[ $STR =~ ((abc)(123)) ]]')
    assert_equal 0, last_status

    rematch = Rubish::Builtins.get_array('RUBISH_REMATCH')
    assert_equal 'abc123', rematch[0]  # Full match
    assert_equal 'abc123', rematch[1]  # Outer group
    assert_equal 'abc', rematch[2]     # First inner group
    assert_equal '123', rematch[3]     # Second inner group
  end

  def test_rubish_rematch_keys
    output_file = File.join(@tempdir, 'output.txt')
    execute('STR="a1b2"')
    execute('[[ $STR =~ (a)(1)(b)(2) ]]')
    execute("echo ${!RUBISH_REMATCH[@]} > #{output_file}")

    value = File.read(output_file).strip
    assert_equal '0 1 2 3 4', value
  end
end
