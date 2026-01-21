# frozen_string_literal: true

require_relative 'test_helper'

class TestRubyExpression < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_ruby_expr_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # ==========================================================================
  # Ruby expression evaluation (inputs starting with capital letter)
  # ==========================================================================

  def test_constant_evaluation
    out = capture_stdout { execute('Object') }
    assert_equal "Object\n", out
  end

  def test_class_method_call
    out = capture_stdout { execute("File.exist?('README.md')") }
    assert_equal "true\n", out
  end

  def test_class_ancestors
    out = capture_stdout { execute('String.ancestors') }
    assert_match(/String/, out)
    assert_match(/Object/, out)
    assert_match(/Kernel/, out)
  end

  def test_math_constant
    out = capture_stdout { execute('Math::PI') }
    assert_match(/3\.14159/, out)
  end

  def test_array_new_with_block
    out = capture_stdout { execute('Array.new(3) { |i| i * 2 }') }
    assert_equal "[0, 2, 4]\n", out
  end

  def test_time_now
    out = capture_stdout { execute('Time.now') }
    assert_match(/\d{4}-\d{2}-\d{2}/, out)
  end

  def test_file_basename
    out = capture_stdout { execute('File.basename("/path/to/file.txt")') }
    assert_equal "\"file.txt\"\n", out
  end

  def test_string_class_methods
    out = capture_stdout { execute('String.new("hello").upcase') }
    assert_equal "\"HELLO\"\n", out
  end

  def test_hash_creation
    out = capture_stdout { execute('Hash[a: 1, b: 2]') }
    assert_match(/a.*1/, out)
    assert_match(/b.*2/, out)
  end

  def test_range_to_array
    out = capture_stdout { execute('Range.new(1, 5).to_a') }
    assert_equal "[1, 2, 3, 4, 5]\n", out
  end

  # ==========================================================================
  # Error handling
  # ==========================================================================

  def test_undefined_constant_error
    err = capture_stderr { execute('UndefinedConstant') }
    assert_match(/uninitialized constant/, err)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  def test_syntax_error
    err = capture_stderr { execute('Array.new(') }
    assert_match(/syntax error|unexpected/, err.downcase)
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end

  # ==========================================================================
  # Variable assignments should NOT be treated as Ruby expressions
  # ==========================================================================

  def test_simple_assignment_not_ruby
    execute('FOO=bar')
    execute("echo $FOO > #{output_file}")
    assert_equal "bar\n", File.read(output_file)
  end

  def test_array_element_assignment_not_ruby
    execute('ARR=(a b c)')
    execute('ARR[1]=changed')
    execute("echo ${ARR[1]} > #{output_file}")
    assert_equal "changed\n", File.read(output_file)
  end

  def test_assignment_with_spaces_not_ruby
    # PATH=/usr/bin should not be treated as Ruby
    execute('MY_PATH=/usr/bin')
    execute("echo $MY_PATH > #{output_file}")
    assert_equal "/usr/bin\n", File.read(output_file)
  end

  # ==========================================================================
  # Regular commands still work
  # ==========================================================================

  def test_regular_command_still_works
    execute("echo hello > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  def test_lowercase_command_not_affected
    execute("printf 'test' > #{output_file}")
    assert_equal 'test', File.read(output_file)
  end
end
