# frozen_string_literal: true

require_relative 'test_helper'

class TestPIPESTATUS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_pipestatus_test')
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Basic PIPESTATUS functionality

  def test_pipestatus_single_success_command
    execute('true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[0]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 0, value
  end

  def test_pipestatus_single_failure_command
    execute('false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[0]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_pipestatus_pipeline_all_success
    execute('true | true | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 0 0', value
  end

  def test_pipestatus_pipeline_first_fails
    execute('false | true | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1 0 0', value
  end

  def test_pipestatus_pipeline_middle_fails
    execute('true | false | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 0', value
  end

  def test_pipestatus_pipeline_last_fails
    execute('true | true | false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 0 1', value
  end

  def test_pipestatus_pipeline_all_fail
    execute('false | false | false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1 1 1', value
  end

  def test_pipestatus_individual_elements
    execute('false | true | false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[0]} ${PIPESTATUS[1]} ${PIPESTATUS[2]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1 0 1', value
  end

  # Array operations

  def test_pipestatus_length
    execute('true | false | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_pipestatus_length_single_command
    execute('true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_pipestatus_keys
    execute('true | false | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 2', value
  end

  def test_pipestatus_star_expansion
    execute('true | false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[*]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1', value
  end

  # Updates after each command

  def test_pipestatus_updates_after_each_command
    execute('false | true')
    output_file1 = File.join(@tempdir, 'output1.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file1}")
    value1 = File.read(output_file1).strip

    execute('true | false | true')
    output_file2 = File.join(@tempdir, 'output2.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file2}")
    value2 = File.read(output_file2).strip

    # First pipeline had 2 commands
    assert_equal '1 0', value1
    # Second pipeline had 3 commands
    assert_equal '0 1 0', value2
  end

  def test_pipestatus_reset_after_simple_command
    execute('false | true | false')
    execute('true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    # After simple command, PIPESTATUS should have single element
    assert_equal '0', value
  end

  # Read-only behavior

  def test_pipestatus_assignment_ignored
    execute('false | true')
    execute('PIPESTATUS=something')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[0]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Should still reflect the last pipeline, not the assignment
    assert_equal 0, value  # echo command's status
  end

  def test_pipestatus_not_stored_in_env
    assert_nil ENV['PIPESTATUS'], 'PIPESTATUS should not be stored in ENV'
    execute('true | false')
    assert_nil ENV['PIPESTATUS'], 'PIPESTATUS should still not be in ENV after pipeline'
  end

  # Edge cases

  def test_pipestatus_out_of_bounds
    execute('true | false')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${PIPESTATUS[99]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_pipestatus_negative_index
    execute('true | false | true')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${PIPESTATUS[-1]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    # Last element (true = 0)
    assert_equal 0, value
  end

  def test_pipestatus_two_command_pipeline
    execute('echo hello | cat')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_pipestatus_initial_value
    # Fresh REPL should have PIPESTATUS = [0]
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    repl.send(:execute, "echo ${PIPESTATUS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value
  end
end
