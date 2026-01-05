# frozen_string_literal: true

require_relative 'test_helper'

class TestDIRSTACK < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = File.realpath(Dir.mktmpdir('rubish_dirstack_test'))
    @subdir1 = File.join(@tempdir, 'dir1')
    @subdir2 = File.join(@tempdir, 'dir2')
    FileUtils.mkdir_p(@subdir1)
    FileUtils.mkdir_p(@subdir2)
    Rubish::Builtins.clear_dir_stack
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    Rubish::Builtins.clear_dir_stack
  end

  def realpath(path)
    File.realpath(path)
  end

  # Basic DIRSTACK functionality

  def test_dirstack_contains_current_directory
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[0]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal realpath(@tempdir), realpath(value)
  end

  def test_dirstack_length_initially_one
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 1, value
  end

  def test_dirstack_after_pushd
    # Use Builtins directly to avoid redirection issues
    Rubish::Builtins.run('pushd', [@subdir1])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip
    parts = value.split
    assert_equal 2, parts.length
    assert_equal realpath(@subdir1), realpath(parts[0])
    assert_equal realpath(@tempdir), realpath(parts[1])
  end

  def test_dirstack_length_after_pushd
    Rubish::Builtins.run('pushd', [@subdir1])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_dirstack_multiple_pushd
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 3, value
  end

  def test_dirstack_index_access
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[0]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal realpath(@subdir2), realpath(value)
  end

  def test_dirstack_second_element
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[1]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal realpath(@subdir1), realpath(value)
  end

  def test_dirstack_after_popd
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    Rubish::Builtins.run('popd', [])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_dirstack_keys
    Rubish::Builtins.run('pushd', [@subdir1])
    Rubish::Builtins.run('pushd', [@subdir2])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${!DIRSTACK[@]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '0 1 2', value
  end

  # Read-only behavior

  def test_dirstack_assignment_ignored
    execute('DIRSTACK=custom')
    # DIRSTACK should still reflect the actual directory stack
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[0]} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal realpath(@tempdir), realpath(value)
  end

  def test_dirstack_not_stored_in_env
    assert_nil ENV['DIRSTACK'], 'DIRSTACK should not be stored in ENV'
    execute('echo ${DIRSTACK[@]}')
    assert_nil ENV['DIRSTACK'], 'DIRSTACK should still not be in ENV after access'
  end

  # Edge cases

  def test_dirstack_out_of_bounds
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo \"x${DIRSTACK[99]}x\" > #{output_file}")
    value = File.read(output_file).strip
    assert_equal 'xx', value
  end

  def test_dirstack_negative_index
    Rubish::Builtins.run('pushd', [@subdir1])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[-1]} > #{output_file}")
    value = File.read(output_file).strip
    # Last element should be tempdir
    assert_equal realpath(@tempdir), realpath(value)
  end

  def test_dirstack_star_expansion
    Rubish::Builtins.run('pushd', [@subdir1])
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${#DIRSTACK[*]} > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 2, value
  end

  def test_dirstack_reflects_cd_changes
    execute("cd #{@subdir1}")
    output_file = File.join(@tempdir, 'output.txt')
    execute("echo ${DIRSTACK[0]} > #{output_file}")
    value = File.read(output_file).strip
    # DIRSTACK[0] should be the current directory
    assert_equal realpath(@subdir1), realpath(value)
  end
end
