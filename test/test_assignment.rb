# frozen_string_literal: true

require_relative 'test_helper'

class TestAssignment < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_assign_test')
    @saved_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @saved_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  # Simple assignments
  def test_simple_assignment
    execute('X=hello')
    assert_equal 'hello', ENV['X']
  end

  def test_assignment_with_numbers
    execute('NUM=42')
    assert_equal '42', ENV['NUM']
  end

  def test_empty_assignment
    execute('EMPTY=')
    assert_equal '', ENV['EMPTY']
  end

  # Multiple assignments
  def test_multiple_assignments
    execute('A=1 B=2 C=3')
    assert_equal '1', ENV['A']
    assert_equal '2', ENV['B']
    assert_equal '3', ENV['C']
  end

  # Variable expansion
  def test_assignment_with_variable
    ENV['SRC'] = 'source'
    execute('DST=$SRC')
    assert_equal 'source', ENV['DST']
  end

  def test_assignment_with_braced_variable
    ENV['VAR'] = 'value'
    execute('COPY=${VAR}')
    assert_equal 'value', ENV['COPY']
  end

  # Arithmetic expansion
  def test_assignment_with_arithmetic
    execute('RESULT=$((10 + 5))')
    assert_equal '15', ENV['RESULT']
  end

  def test_assignment_with_complex_arithmetic
    ENV['X'] = '3'
    execute('Y=$((X * X))')
    assert_equal '9', ENV['Y']
  end

  # Command substitution
  def test_assignment_with_command_substitution
    execute('PWD_VAR=$(pwd)')
    assert_equal Dir.pwd, ENV['PWD_VAR']
  end

  # Quoted values
  def test_assignment_single_quoted
    execute("MSG='hello world'")
    assert_equal 'hello world', ENV['MSG']
  end

  def test_assignment_double_quoted
    ENV['NAME'] = 'Ruby'
    execute('GREETING="Hello $NAME"')
    assert_equal 'Hello Ruby', ENV['GREETING']
  end

  def test_assignment_single_quoted_no_expansion
    ENV['VAR'] = 'value'
    execute("LITERAL='$VAR'")
    assert_equal '$VAR', ENV['LITERAL']
  end

  # Used in echo
  def test_assignment_then_echo
    execute('MSG=hello')
    execute("echo $MSG > #{output_file}")
    assert_equal "hello\n", File.read(output_file)
  end

  # Underscore in variable names
  def test_underscore_variable
    execute('MY_VAR=test')
    assert_equal 'test', ENV['MY_VAR']
  end

  def test_leading_underscore
    execute('_PRIVATE=secret')
    assert_equal 'secret', ENV['_PRIVATE']
  end

  # Path-like values
  def test_path_value
    execute('MY_PATH=/usr/local/bin')
    assert_equal '/usr/local/bin', ENV['MY_PATH']
  end

  # Overwrite existing
  def test_overwrite_variable
    ENV['OVERWRITE'] = 'old'
    execute('OVERWRITE=new')
    assert_equal 'new', ENV['OVERWRITE']
  end
end
