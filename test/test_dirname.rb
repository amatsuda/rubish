# frozen_string_literal: true

require_relative 'test_helper'

class TestDirname < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_dirname_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test basic dirname
  def test_dirname_simple
    output = capture_output { Rubish::Builtins.run('dirname', ['/usr/bin/sort']) }
    assert_equal "/usr/bin\n", output
  end

  def test_dirname_with_file
    output = capture_output { Rubish::Builtins.run('dirname', ['stdio.h']) }
    assert_equal ".\n", output
  end

  def test_dirname_trailing_slash
    output = capture_output { Rubish::Builtins.run('dirname', ['/usr/bin/']) }
    assert_equal "/usr\n", output
  end

  def test_dirname_root
    output = capture_output { Rubish::Builtins.run('dirname', ['/']) }
    assert_equal "/\n", output
  end

  def test_dirname_multiple_args
    output = capture_output { Rubish::Builtins.run('dirname', ['/foo/bar', '/baz/qux/file.txt']) }
    assert_equal "/foo\n/baz/qux\n", output
  end

  def test_dirname_relative_path
    output = capture_output { Rubish::Builtins.run('dirname', ['foo/bar/baz']) }
    assert_equal "foo/bar\n", output
  end

  def test_dirname_current_dir
    output = capture_output { Rubish::Builtins.run('dirname', ['.']) }
    assert_equal ".\n", output
  end

  def test_dirname_parent_dir
    output = capture_output { Rubish::Builtins.run('dirname', ['..']) }
    assert_equal ".\n", output
  end

  # Test -z flag (NUL terminated)
  def test_dirname_zero_terminated
    output = capture_output { Rubish::Builtins.run('dirname', ['-z', '/foo/bar']) }
    assert_equal "/foo\0", output
  end

  def test_dirname_zero_multiple
    output = capture_output { Rubish::Builtins.run('dirname', ['-z', '/foo/bar', '/baz/qux']) }
    assert_equal "/foo\0/baz\0", output
  end

  # Test missing operand error
  def test_dirname_no_args
    output = capture_stderr { Rubish::Builtins.run('dirname', []) }
    assert_match(/missing operand/, output)
  end

  # Test invalid option
  def test_dirname_invalid_option
    output = capture_stderr { Rubish::Builtins.run('dirname', ['-x', '/foo/bar']) }
    assert_match(/invalid option/, output)
  end

  # Test via REPL
  def test_dirname_via_repl
    file = File.join(@tempdir, 'output.txt')
    execute("dirname /usr/local/bin/ruby > #{file}")
    content = File.read(file).strip
    assert_equal '/usr/local/bin', content
  end

  def test_dirname_returns_true_on_success
    capture_output do
      result = Rubish::Builtins.run('dirname', ['/foo/bar'])
      assert result
    end
  end

  def test_dirname_returns_false_on_error
    capture_stderr do
      result = Rubish::Builtins.run('dirname', [])
      assert_false result
    end
  end

  # Test double dash
  def test_dirname_double_dash
    output = capture_output { Rubish::Builtins.run('dirname', ['--', '-z']) }
    assert_equal ".\n", output
  end
end
