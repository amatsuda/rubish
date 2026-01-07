# frozen_string_literal: true

require_relative 'test_helper'

class TestCheckhash < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.shell_options.dup
    @original_set_options = Rubish::Builtins.set_options.dup
    @original_path = ENV['PATH']
    @tempdir = Dir.mktmpdir('rubish_checkhash_test')
    @bin_dir = File.join(@tempdir, 'bin')
    Dir.mkdir(@bin_dir)
    Rubish::Builtins.clear_hash
  end

  def teardown
    Rubish::Builtins.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.shell_options[k] = v }
    Rubish::Builtins.set_options.clear
    @original_set_options.each { |k, v| Rubish::Builtins.set_options[k] = v }
    ENV['PATH'] = @original_path
    FileUtils.rm_rf(@tempdir)
    Rubish::Builtins.clear_hash
  end

  def create_executable(name, content = "#!/bin/sh\necho #{name}")
    path = File.join(@bin_dir, name)
    File.write(path, content)
    File.chmod(0o755, path)
    path
  end

  # checkhash is disabled by default
  def test_checkhash_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('checkhash')
  end

  def test_checkhash_can_be_enabled
    execute('shopt -s checkhash')
    assert Rubish::Builtins.shopt_enabled?('checkhash')
  end

  def test_checkhash_can_be_disabled
    execute('shopt -s checkhash')
    execute('shopt -u checkhash')
    assert_false Rubish::Builtins.shopt_enabled?('checkhash')
  end

  # Test hash_delete method
  def test_hash_delete
    Rubish::Builtins.hash_store('mytest', '/usr/bin/mytest')
    assert_equal '/usr/bin/mytest', Rubish::Builtins.hash_lookup('mytest')

    Rubish::Builtins.hash_delete('mytest')
    assert_nil Rubish::Builtins.hash_lookup('mytest')
  end

  # Without checkhash, stale hash entries are used as-is
  def test_stale_hash_used_without_checkhash
    # Create a command and hash it
    cmd_path = create_executable('mycmd')
    ENV['PATH'] = "#{@bin_dir}:#{@original_path}"

    # Enable hashall (set -h) which is default
    execute('set -h')

    # Store in hash
    Rubish::Builtins.hash_store('mycmd', cmd_path)

    # Remove the executable
    File.delete(cmd_path)

    # Without checkhash, resolve_command_path should return the stale path
    cmd = Rubish::Command.new('mycmd')
    resolved = cmd.send(:resolve_command_path, 'mycmd')
    assert_equal cmd_path, resolved
  end

  # With checkhash, stale hash entries are detected and removed
  def test_stale_hash_detected_with_checkhash
    # Create two executables in different locations
    old_bin = File.join(@tempdir, 'old_bin')
    new_bin = File.join(@tempdir, 'new_bin')
    Dir.mkdir(old_bin)
    Dir.mkdir(new_bin)

    old_cmd = File.join(old_bin, 'mycmd')
    new_cmd = File.join(new_bin, 'mycmd')

    File.write(old_cmd, "#!/bin/sh\necho old")
    File.chmod(0o755, old_cmd)
    File.write(new_cmd, "#!/bin/sh\necho new")
    File.chmod(0o755, new_cmd)

    # PATH has new_bin first, then old_bin
    ENV['PATH'] = "#{new_bin}:#{old_bin}:#{@original_path}"

    execute('set -h')
    execute('shopt -s checkhash')

    # Manually store the OLD path in hash (simulating stale cache)
    Rubish::Builtins.hash_store('mycmd', old_cmd)

    # Remove the old executable
    File.delete(old_cmd)

    # With checkhash, resolve should detect stale path and find the new one
    cmd = Rubish::Command.new('mycmd')
    resolved = cmd.send(:resolve_command_path, 'mycmd')
    assert_equal new_cmd, resolved

    # Hash should now contain the new path
    assert_equal new_cmd, Rubish::Builtins.hash_lookup('mycmd')
  end

  # Test that checkhash removes stale entry even if command not found elsewhere
  def test_stale_hash_removed_command_not_found
    execute('set -h')
    execute('shopt -s checkhash')

    # Store a fake path
    fake_path = '/nonexistent/path/to/cmd'
    Rubish::Builtins.hash_store('fakecmd', fake_path)

    # resolve should detect it's invalid and remove from hash
    cmd = Rubish::Command.new('fakecmd')
    resolved = cmd.send(:resolve_command_path, 'fakecmd')

    # Should return 'fakecmd' (not found in PATH)
    assert_equal 'fakecmd', resolved

    # Hash should no longer contain the stale entry
    assert_nil Rubish::Builtins.hash_lookup('fakecmd')
  end

  # Test that valid hash entries are still used with checkhash
  def test_valid_hash_used_with_checkhash
    cmd_path = create_executable('validcmd')
    ENV['PATH'] = "#{@bin_dir}:#{@original_path}"

    execute('set -h')
    execute('shopt -s checkhash')

    # Store valid path
    Rubish::Builtins.hash_store('validcmd', cmd_path)

    # Should use the cached path
    cmd = Rubish::Command.new('validcmd')
    resolved = cmd.send(:resolve_command_path, 'validcmd')
    assert_equal cmd_path, resolved

    # Hash should still contain the path
    assert_equal cmd_path, Rubish::Builtins.hash_lookup('validcmd')
  end

  # Test that checkhash detects when file becomes non-executable
  def test_checkhash_detects_non_executable
    cmd_path = create_executable('nonexeccmd')
    ENV['PATH'] = "#{@bin_dir}:#{@original_path}"

    execute('set -h')
    execute('shopt -s checkhash')

    # Store in hash
    Rubish::Builtins.hash_store('nonexeccmd', cmd_path)

    # Make it non-executable
    File.chmod(0o644, cmd_path)

    # Should detect it's no longer executable
    cmd = Rubish::Command.new('nonexeccmd')
    resolved = cmd.send(:resolve_command_path, 'nonexeccmd')

    # Should return 'nonexeccmd' (can't execute)
    assert_equal 'nonexeccmd', resolved

    # Hash should be cleared
    assert_nil Rubish::Builtins.hash_lookup('nonexeccmd')
  end

  # Test that checkhash detects when path becomes a directory
  def test_checkhash_detects_directory
    cmd_path = create_executable('dircmd')
    ENV['PATH'] = "#{@bin_dir}:#{@original_path}"

    execute('set -h')
    execute('shopt -s checkhash')

    # Store in hash
    Rubish::Builtins.hash_store('dircmd', cmd_path)

    # Remove file and create directory with same name
    File.delete(cmd_path)
    Dir.mkdir(cmd_path)

    # Should detect it's now a directory
    cmd = Rubish::Command.new('dircmd')
    resolved = cmd.send(:resolve_command_path, 'dircmd')

    # Should return 'dircmd' (not executable)
    assert_equal 'dircmd', resolved

    # Hash should be cleared
    assert_nil Rubish::Builtins.hash_lookup('dircmd')
  end

  # Test hashall disabled bypasses hash entirely
  def test_hashall_disabled_bypasses_hash
    cmd_path = create_executable('hashcmd')
    ENV['PATH'] = "#{@bin_dir}:#{@original_path}"

    execute('set +h')  # Disable hashall
    execute('shopt -s checkhash')

    # Store in hash
    Rubish::Builtins.hash_store('hashcmd', cmd_path)

    # With hashall disabled, should not use hash
    cmd = Rubish::Command.new('hashcmd')
    resolved = cmd.send(:resolve_command_path, 'hashcmd')

    # Returns the command name, not from hash (since hashall is off)
    assert_equal 'hashcmd', resolved
  end

  # Test absolute path bypasses hash
  def test_absolute_path_bypasses_hash
    cmd_path = create_executable('abscmd')

    execute('set -h')
    execute('shopt -s checkhash')

    # Absolute path should be returned as-is
    cmd = Rubish::Command.new(cmd_path)
    resolved = cmd.send(:resolve_command_path, cmd_path)
    assert_equal cmd_path, resolved
  end

  # Test relative path with slash bypasses hash
  def test_relative_path_bypasses_hash
    execute('set -h')
    execute('shopt -s checkhash')

    # Relative path with slash should be returned as-is
    cmd = Rubish::Command.new('./mycmd')
    resolved = cmd.send(:resolve_command_path, './mycmd')
    assert_equal './mycmd', resolved
  end
end
