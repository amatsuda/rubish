# frozen_string_literal: true

require_relative 'test_helper'

class TestRealpath < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_realpath_test')
    @original_dir = Dir.pwd
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test basic realpath
  def test_realpath_simple
    output = capture_output { Rubish::Builtins.run('realpath', [@tempdir]) }
    assert_equal "#{File.realpath(@tempdir)}\n", output
  end

  def test_realpath_relative
    Dir.chdir(@tempdir)
    output = capture_output { Rubish::Builtins.run('realpath', ['.']) }
    assert_equal "#{File.realpath(@tempdir)}\n", output
  end

  def test_realpath_with_file
    file = File.join(@tempdir, 'test.txt')
    File.write(file, 'test')
    output = capture_output { Rubish::Builtins.run('realpath', [file]) }
    assert_equal "#{File.realpath(file)}\n", output
  end

  def test_realpath_symlink
    target = File.join(@tempdir, 'target')
    link = File.join(@tempdir, 'link')
    File.write(target, 'content')
    File.symlink(target, link)

    output = capture_output { Rubish::Builtins.run('realpath', [link]) }
    assert_equal "#{File.realpath(target)}\n", output
  end

  def test_realpath_multiple_args
    file1 = File.join(@tempdir, 'file1')
    file2 = File.join(@tempdir, 'file2')
    File.write(file1, 'a')
    File.write(file2, 'b')

    output = capture_output { Rubish::Builtins.run('realpath', [file1, file2]) }
    lines = output.strip.split("\n")
    assert_equal 2, lines.length
    assert_equal File.realpath(file1), lines[0]
    assert_equal File.realpath(file2), lines[1]
  end

  # Test non-existent file (default: error)
  def test_realpath_nonexistent
    nonexistent = File.join(@tempdir, 'nonexistent')
    output = capture_stderr do
      result = Rubish::Builtins.run('realpath', [nonexistent])
      assert_false result
    end
    assert_match(/No such file or directory/, output)
  end

  # Test -m flag (canonicalize missing)
  def test_realpath_missing_mode
    nonexistent = File.join(@tempdir, 'nonexistent', 'deep', 'path')
    output = capture_output { Rubish::Builtins.run('realpath', ['-m', nonexistent]) }
    assert_match(%r{#{@tempdir}/nonexistent/deep/path}, output)
  end

  # Test -q flag (quiet)
  def test_realpath_quiet
    nonexistent = File.join(@tempdir, 'nonexistent')
    output = capture_stderr do
      result = Rubish::Builtins.run('realpath', ['-q', nonexistent])
      assert_false result
    end
    assert_equal '', output
  end

  # Test -s flag (no symlinks)
  def test_realpath_no_symlinks
    target = File.join(@tempdir, 'target')
    link = File.join(@tempdir, 'link')
    File.write(target, 'content')
    File.symlink(target, link)

    output = capture_output { Rubish::Builtins.run('realpath', ['-s', link]) }
    # Should return the symlink path itself, not the target
    assert_equal "#{File.expand_path(link)}\n", output
  end

  # Test -z flag (NUL terminated)
  def test_realpath_zero_terminated
    output = capture_output { Rubish::Builtins.run('realpath', ['-z', @tempdir]) }
    assert_equal "#{File.realpath(@tempdir)}\0", output
  end

  # Test missing operand error
  def test_realpath_no_args
    output = capture_stderr { Rubish::Builtins.run('realpath', []) }
    assert_match(/missing operand/, output)
  end

  # Test invalid option
  def test_realpath_invalid_option
    output = capture_stderr { Rubish::Builtins.run('realpath', ['-x', @tempdir]) }
    assert_match(/invalid option/, output)
  end

  # Test via REPL
  def test_realpath_via_repl
    file = File.join(@tempdir, 'output.txt')
    execute("realpath #{@tempdir} > #{file}")
    content = File.read(file).strip
    assert_equal File.realpath(@tempdir), content
  end

  def test_realpath_returns_true_on_success
    capture_output do
      result = Rubish::Builtins.run('realpath', [@tempdir])
      assert result
    end
  end

  def test_realpath_returns_false_on_error
    capture_stderr do
      result = Rubish::Builtins.run('realpath', [])
      assert_false result
    end
  end

  # Test partial success (some files exist, some don't)
  def test_realpath_partial_success
    existing = File.join(@tempdir, 'exists')
    nonexistent = File.join(@tempdir, 'nonexistent')
    File.write(existing, 'content')

    stdout_output = nil
    stderr_output = nil

    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    result = Rubish::Builtins.run('realpath', [existing, nonexistent])

    stdout_output = $stdout.string
    stderr_output = $stderr.string
    $stdout = original_stdout
    $stderr = original_stderr

    assert_false result
    assert_match(/#{File.realpath(existing)}/, stdout_output)
    assert_match(/No such file or directory/, stderr_output)
  end

  # Test double dash
  def test_realpath_double_dash
    output = capture_output { Rubish::Builtins.run('realpath', ['-m', '--', '-s']) }
    # -s should be treated as filename after --
    assert_match(%r{-s$}, output.strip)
  end
end
