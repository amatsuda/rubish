# frozen_string_literal: true

require_relative 'test_helper'

class TestRUBISH_CMDS < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_cmds_test')
    Dir.chdir(@tempdir)
    Rubish::Builtins.clear_hash
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_hash
  end

  # Basic RUBISH_CMDS functionality

  def test_rubish_cmds_empty_initially
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value
  end

  def test_rubish_cmds_populated_after_hash
    execute('hash ls')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert value >= 1, 'Expected at least 1 command in hash'
  end

  def test_rubish_cmds_get_path_by_name
    execute('hash ls')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_CMDS[ls]} > #{output_file}")
    value = File.read(output_file).strip
    assert value.end_with?('ls'), "Expected path ending with 'ls', got: #{value}"
    assert value.start_with?('/'), "Expected absolute path, got: #{value}"
  end

  def test_rubish_cmds_get_all_values
    execute('hash ls cat')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert value.include?('/'), 'Should contain path separators'
  end

  def test_rubish_cmds_get_all_keys
    execute('hash ls cat')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    keys = value.split
    assert_include keys, 'ls'
    assert_include keys, 'cat'
  end

  def test_rubish_cmds_nonexistent_key
    execute('hash ls')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${RUBISH_CMDS[nonexistent]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_rubish_cmds_after_hash_r
    execute('hash ls cat')
    execute('hash -r')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0', value
  end

  def test_rubish_cmds_after_hash_d
    execute('hash ls cat')
    execute('hash -d ls')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!RUBISH_CMDS[@]} > #{output_file}")
    value = File.read(output_file).strip
    keys = value.split
    assert_not_include keys, 'ls'
    assert_include keys, 'cat'
  end

  # Read-only behavior

  def test_rubish_cmds_assignment_ignored
    execute('hash ls')
    execute('RUBISH_CMDS=custom')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_CMDS[ls]} > #{output_file}")
    value = File.read(output_file).strip
    assert value.end_with?('ls'), 'Should still have ls path'
  end

  def test_rubish_cmds_not_in_env
    execute('hash ls')
    assert_nil ENV['RUBISH_CMDS'], 'RUBISH_CMDS should not be in ENV'
  end

  # Conditional tests

  def test_rubish_cmds_in_conditional
    execute('hash ls')
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n ${RUBISH_CMDS[ls]} ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'yes', value
  end

  def test_rubish_cmds_nonexistent_in_conditional
    output_file = File.join(@tempdir, 'output.txt')
    execute("if [[ -n ${RUBISH_CMDS[nonexistent]} ]]; then echo yes; else echo no; fi > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'no', value
  end

  # Star expansion

  def test_rubish_cmds_star_expansion
    execute('hash ls cat')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#RUBISH_CMDS[*]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '2', value
  end

  # Direct access to command_hash

  def test_direct_hash_store_visible
    Rubish::Builtins.hash_store('mytest', '/usr/bin/mytest')
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${RUBISH_CMDS[mytest]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '/usr/bin/mytest', value
  end
end
