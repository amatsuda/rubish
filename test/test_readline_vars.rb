# frozen_string_literal: true

require_relative 'test_helper'

class TestReadlineVars < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_readline_vars_test')
    @original_dir = Dir.pwd
    Dir.chdir(@tempdir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # READLINE_LINE tests

  def test_readline_line_default_empty
    execute("echo \"x${READLINE_LINE}x\" > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'xx', result
  end

  def test_readline_line_can_be_set
    execute('READLINE_LINE=hello')
    assert_equal 'hello', Rubish::Builtins.readline_line
  end

  def test_readline_line_can_be_read
    Rubish::Builtins.readline_line = 'test line'
    execute("echo $READLINE_LINE > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'test line', result
  end

  def test_readline_line_assignment_and_read
    execute('READLINE_LINE="some text here"')
    execute("echo $READLINE_LINE > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'some text here', result
  end

  def test_readline_line_with_spaces
    execute('READLINE_LINE="hello world"')
    assert_equal 'hello world', Rubish::Builtins.readline_line
  end

  # READLINE_POINT tests

  def test_readline_point_default_zero
    execute("echo $READLINE_POINT > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '0', result
  end

  def test_readline_point_can_be_set
    execute('READLINE_POINT=5')
    assert_equal 5, Rubish::Builtins.readline_point
  end

  def test_readline_point_can_be_read
    Rubish::Builtins.readline_point = 10
    execute("echo $READLINE_POINT > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '10', result
  end

  def test_readline_point_assignment_and_read
    execute('READLINE_POINT=15')
    execute("echo $READLINE_POINT > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '15', result
  end

  def test_readline_point_converts_to_integer
    execute('READLINE_POINT="42"')
    assert_equal 42, Rubish::Builtins.readline_point
  end

  # READLINE_MARK tests

  def test_readline_mark_default_zero
    execute("echo $READLINE_MARK > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '0', result
  end

  def test_readline_mark_can_be_set
    execute('READLINE_MARK=3')
    assert_equal 3, Rubish::Builtins.readline_mark
  end

  def test_readline_mark_can_be_read
    Rubish::Builtins.readline_mark = 7
    execute("echo $READLINE_MARK > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '7', result
  end

  def test_readline_mark_assignment_and_read
    execute('READLINE_MARK=20')
    execute("echo $READLINE_MARK > #{output_file}")
    result = File.read(output_file).strip
    assert_equal '20', result
  end

  def test_readline_mark_converts_to_integer
    execute('READLINE_MARK="99"')
    assert_equal 99, Rubish::Builtins.readline_mark
  end

  # Parameter expansion tests

  def test_readline_line_default_expansion
    execute("echo ${READLINE_LINE:-default} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'default', result
  end

  def test_readline_line_default_expansion_when_set
    execute('READLINE_LINE=value')
    execute("echo ${READLINE_LINE:-default} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'value', result
  end

  def test_readline_point_alternate_expansion
    execute('READLINE_POINT=5')
    execute("echo ${READLINE_POINT:+set} > #{output_file}")
    result = File.read(output_file).strip
    assert_equal 'set', result
  end

  # Combined usage test

  def test_combined_readline_vars
    execute('READLINE_LINE="hello world"')
    execute('READLINE_POINT=5')
    execute('READLINE_MARK=0')

    execute("echo \"$READLINE_LINE\" > #{output_file}")
    line = File.read(output_file).strip
    assert_equal 'hello world', line

    execute("echo $READLINE_POINT > #{output_file}")
    point = File.read(output_file).strip
    assert_equal '5', point

    execute("echo $READLINE_MARK > #{output_file}")
    mark = File.read(output_file).strip
    assert_equal '0', mark
  end

  # Test builtins methods exist

  def test_builtins_readline_line_method
    assert_respond_to Rubish::Builtins, :readline_line
    assert_respond_to Rubish::Builtins, :readline_line=
  end

  def test_builtins_readline_point_method
    assert_respond_to Rubish::Builtins, :readline_point
    assert_respond_to Rubish::Builtins, :readline_point=
  end

  def test_builtins_readline_mark_method
    assert_respond_to Rubish::Builtins, :readline_mark
    assert_respond_to Rubish::Builtins, :readline_mark=
  end

  # Test that variables don't leak to ENV

  def test_readline_line_not_in_env
    execute('READLINE_LINE=test')
    assert_nil ENV['READLINE_LINE']
  end

  def test_readline_point_not_in_env
    execute('READLINE_POINT=10')
    assert_nil ENV['READLINE_POINT']
  end

  def test_readline_mark_not_in_env
    execute('READLINE_MARK=5')
    assert_nil ENV['READLINE_MARK']
  end
end
