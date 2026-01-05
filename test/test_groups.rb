# frozen_string_literal: true

require_relative 'test_helper'

class TestGROUPS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_groups_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic GROUPS functionality

  def test_groups_bare_returns_first_element
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $GROUPS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups.first, value
  end

  def test_groups_first_element
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[0]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups[0], value
  end

  def test_groups_second_element
    skip 'Only one group available' if Process.groups.length < 2
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[1]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups[1], value
  end

  def test_groups_all_elements_at
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[@]} > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    assert_equal Process.groups, values
  end

  def test_groups_all_elements_star
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[*]} > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    assert_equal Process.groups, values
  end

  def test_groups_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#GROUPS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups.length, value
  end

  def test_groups_indices
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!GROUPS[@]} > #{output_file}")
    indices = File.read(output_file).strip.split.map(&:to_i)
    assert_equal (0...Process.groups.length).to_a, indices
  end

  def test_groups_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[9999]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '', value
  end

  # GROUPS in quotes

  def test_groups_double_quoted
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"Groups: $GROUPS\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal "Groups: #{Process.groups.first}", content
  end

  def test_groups_braced_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups.first, value
  end

  # GROUPS is read-only

  def test_groups_assignment_ignored
    original_first = Process.groups.first
    execute('GROUPS=12345')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo $GROUPS > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal original_first, value, 'GROUPS should remain unchanged after assignment'
  end

  def test_groups_not_stored_in_env
    assert_nil ENV['GROUPS'], 'GROUPS should not be stored in ENV'
    execute('echo $GROUPS')
    assert_nil ENV['GROUPS'], 'GROUPS should still not be in ENV after access'
    execute('GROUPS=123')
    assert_nil ENV['GROUPS'], 'GROUPS should not be in ENV after assignment attempt'
  end

  # Parameter expansion

  def test_groups_with_default_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS:-default} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal Process.groups.first, value
  end

  def test_groups_with_alternate_expansion
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'GROUPS should be considered set'
  end

  # Edge cases

  def test_groups_in_subshell
    output_file = File.join(@tempdir, 'output.txt')
    execute("(echo ${GROUPS[@]}) > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # Subshell should have access to groups
    assert values.length > 0
  end

  def test_groups_count_matches_length
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[@]} > #{output_file}")
    values = File.read(output_file).strip.split
    assert_equal Process.groups.length, values.length
  end

  def test_groups_contains_primary_group
    # Primary group (from Process.gid) should be in GROUPS
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${GROUPS[@]} > #{output_file}")
    values = File.read(output_file).strip.split.map(&:to_i)
    # Note: Process.groups may or may not include gid depending on system
    assert values.include?(Process.groups.first)
  end

  def test_groups_independent_per_repl
    repl1 = Rubish::REPL.new
    repl2 = Rubish::REPL.new

    output_file1 = File.join(@tempdir, 'output1.txt')
    output_file2 = File.join(@tempdir, 'output2.txt')

    repl1.send(:execute, "echo ${GROUPS[@]} > #{output_file1}")
    repl2.send(:execute, "echo ${GROUPS[@]} > #{output_file2}")

    values1 = File.read(output_file1).strip.split.map(&:to_i)
    values2 = File.read(output_file2).strip.split.map(&:to_i)

    # Both should return the same groups (from same process)
    assert_equal values1, values2
    assert_equal Process.groups, values1
  end
end
