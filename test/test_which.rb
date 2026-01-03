# frozen_string_literal: true

require_relative 'test_helper'

class TestWhich < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_which_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test which for common commands
  def test_which_ls
    output = capture_output { Rubish::Builtins.run('which', ['ls']) }
    assert_match(%r{^/.*ls$}, output.strip)
    assert File.executable?(output.strip)
  end

  def test_which_cat
    output = capture_output { Rubish::Builtins.run('which', ['cat']) }
    assert_match(%r{^/.*cat$}, output.strip)
    assert File.executable?(output.strip)
  end

  def test_which_echo
    output = capture_output { Rubish::Builtins.run('which', ['echo']) }
    # echo exists as external command
    assert_match(%r{^/.*echo$}, output.strip)
  end

  # Test which not found
  def test_which_not_found
    output = capture_output { Rubish::Builtins.run('which', ['nonexistent_command_xyz']) }
    assert_match(/not found/, output)
  end

  # Test which returns false for not found
  def test_which_returns_false_for_not_found
    capture_output do
      result = Rubish::Builtins.run('which', ['nonexistent_command_xyz'])
      assert_false result
    end
  end

  # Test which returns true for found
  def test_which_returns_true_for_found
    capture_output do
      result = Rubish::Builtins.run('which', ['ls'])
      assert result
    end
  end

  # Test multiple commands
  def test_which_multiple_commands
    output = capture_output { Rubish::Builtins.run('which', ['ls', 'cat']) }
    lines = output.strip.split("\n")
    assert_equal 2, lines.length
    assert_match(%r{/.*ls}, lines[0])
    assert_match(%r{/.*cat}, lines[1])
  end

  def test_which_multiple_with_not_found
    output = capture_output do
      result = Rubish::Builtins.run('which', ['ls', 'nonexistent_xyz', 'cat'])
      assert_false result  # Returns false if any not found
    end
    assert_match(%r{/.*ls}, output)
    assert_match(/not found/, output)
    assert_match(%r{/.*cat}, output)
  end

  # Test -a flag (show all)
  def test_which_a_flag
    output = capture_output { Rubish::Builtins.run('which', ['-a', 'ls']) }
    # Should show at least one result
    assert_match(%r{^/.*ls$}, output.strip.split("\n").first)
  end

  # Test usage error
  def test_which_no_args
    output = capture_output { Rubish::Builtins.run('which', []) }
    assert_match(/usage/, output)
  end

  def test_which_only_flag
    output = capture_output { Rubish::Builtins.run('which', ['-a']) }
    assert_match(/usage/, output)
  end

  # Test via REPL
  def test_which_via_repl
    file = File.join(@tempdir, 'output.txt')
    execute("which ls > #{file}")
    content = File.read(file).strip
    assert_match(%r{^/.*ls$}, content)
  end

  # Test find_all_in_path helper
  def test_find_all_in_path
    paths = Rubish::Builtins.find_all_in_path('ls')
    assert paths.is_a?(Array)
    assert paths.length >= 1
    paths.each { |p| assert File.executable?(p) }
  end

  def test_find_all_in_path_not_found
    paths = Rubish::Builtins.find_all_in_path('nonexistent_command_xyz')
    assert_equal [], paths
  end

  # Test with custom PATH
  def test_which_custom_path
    # Create a temp executable
    temp_bin = File.join(@tempdir, 'mycommand')
    File.write(temp_bin, "#!/bin/sh\necho hello")
    File.chmod(0o755, temp_bin)

    # Add tempdir to PATH
    old_path = ENV['PATH']
    ENV['PATH'] = "#{@tempdir}:#{old_path}"

    output = capture_output { Rubish::Builtins.run('which', ['mycommand']) }
    assert_equal temp_bin, output.strip

    ENV['PATH'] = old_path
  end

  # Test which with path containing slash
  def test_which_with_slash
    # Create a temp executable
    temp_bin = File.join(@tempdir, 'myexec')
    File.write(temp_bin, "#!/bin/sh\necho hello")
    File.chmod(0o755, temp_bin)

    output = capture_output { Rubish::Builtins.run('which', [temp_bin]) }
    assert_equal temp_bin, output.strip
  end

  def test_which_with_slash_not_executable
    temp_file = File.join(@tempdir, 'notexec')
    File.write(temp_file, 'not executable')
    # Don't make it executable

    output = capture_output { Rubish::Builtins.run('which', [temp_file]) }
    assert_match(/not found/, output)
  end
end
