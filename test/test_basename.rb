# frozen_string_literal: true

require_relative 'test_helper'

class TestBasename < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_basename_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test basic basename
  def test_basename_simple
    output = capture_output { Rubish::Builtins.run('basename', ['/usr/bin/sort']) }
    assert_equal "sort\n", output
  end

  def test_basename_with_suffix
    output = capture_output { Rubish::Builtins.run('basename', ['include/stdio.h', '.h']) }
    assert_equal "stdio\n", output
  end

  def test_basename_suffix_not_matching
    output = capture_output { Rubish::Builtins.run('basename', ['include/stdio.h', '.txt']) }
    assert_equal "stdio.h\n", output
  end

  def test_basename_trailing_slash
    output = capture_output { Rubish::Builtins.run('basename', ['/usr/bin/']) }
    assert_equal "bin\n", output
  end

  def test_basename_just_filename
    output = capture_output { Rubish::Builtins.run('basename', ['file.txt']) }
    assert_equal "file.txt\n", output
  end

  def test_basename_root
    output = capture_output { Rubish::Builtins.run('basename', ['/']) }
    assert_equal "/\n", output
  end

  # Test -a flag (multiple arguments)
  def test_basename_multiple
    output = capture_output { Rubish::Builtins.run('basename', ['-a', '/foo/bar', '/baz/qux']) }
    assert_equal "bar\nqux\n", output
  end

  # Test -s flag (suffix removal for multiple)
  def test_basename_suffix_option
    output = capture_output { Rubish::Builtins.run('basename', ['-s', '.txt', '/foo/bar.txt', '/baz/qux.txt']) }
    assert_equal "bar\nqux\n", output
  end

  def test_basename_suffix_partial_match
    # Suffix should only be removed if it matches and doesn't equal the entire basename
    output = capture_output { Rubish::Builtins.run('basename', ['/foo/.txt', '.txt']) }
    assert_equal ".txt\n", output
  end

  # Test -z flag (NUL terminated)
  def test_basename_zero_terminated
    output = capture_output { Rubish::Builtins.run('basename', ['-z', '/foo/bar']) }
    assert_equal "bar\0", output
  end

  # Test missing operand error
  def test_basename_no_args
    output = capture_stderr { Rubish::Builtins.run('basename', []) }
    assert_match(/missing operand/, output)
  end

  # Test invalid option
  def test_basename_invalid_option
    output = capture_stderr { Rubish::Builtins.run('basename', ['-x', '/foo/bar']) }
    assert_match(/invalid option/, output)
  end

  # Test via REPL
  def test_basename_via_repl
    file = File.join(@tempdir, 'output.txt')
    execute("basename /usr/local/bin/ruby > #{file}")
    content = File.read(file).strip
    assert_equal 'ruby', content
  end

  def test_basename_returns_true_on_success
    capture_output do
      result = Rubish::Builtins.run('basename', ['/foo/bar'])
      assert result
    end
  end

  def test_basename_returns_false_on_error
    capture_stderr do
      result = Rubish::Builtins.run('basename', [])
      assert_false result
    end
  end

  # Test double dash
  def test_basename_double_dash
    output = capture_output { Rubish::Builtins.run('basename', ['--', '-a']) }
    assert_equal "-a\n", output
  end
end
