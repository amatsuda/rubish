# frozen_string_literal: true

require_relative 'test_helper'

class TestShift < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_shift_is_builtin
    assert Rubish::Builtins.builtin?('shift')
  end

  def test_shift_one
    @repl.positional_params = %w[a b c]
    execute('shift')
    assert_equal %w[b c], @repl.positional_params
  end

  def test_shift_default_is_one
    @repl.positional_params = %w[first second third]
    execute('shift')
    assert_equal %w[second third], @repl.positional_params
  end

  def test_shift_by_two
    @repl.positional_params = %w[a b c d e]
    execute('shift 2')
    assert_equal %w[c d e], @repl.positional_params
  end

  def test_shift_by_zero
    @repl.positional_params = %w[a b c]
    execute('shift 0')
    assert_equal %w[a b c], @repl.positional_params
  end

  def test_shift_all
    @repl.positional_params = %w[a b c]
    execute('shift 3')
    assert_equal [], @repl.positional_params
  end

  def test_shift_empty_params
    @repl.positional_params = []
    result = Rubish::Builtins.run('shift', [])
    assert_equal false, result
  end

  def test_shift_out_of_range
    @repl.positional_params = %w[a b]
    output = capture_output { execute('shift 5') }
    assert_match(/out of range/, output)
    # Params should be unchanged
    assert_equal %w[a b], @repl.positional_params
  end

  def test_shift_updates_special_vars
    @repl.positional_params = %w[first second third]
    execute('shift')

    # $1 should now be 'second'
    result = @repl.send(:expand_variables, '$1')
    assert_equal 'second', result

    # $# should be 2
    result = @repl.send(:expand_variables, '$#')
    assert_equal '2', result

    # $@ should be 'second third'
    result = @repl.send(:expand_variables, '$@')
    assert_equal 'second third', result
  end

  def test_shift_in_script
    tempdir = Dir.mktmpdir('rubish_shift_test')
    output_file = File.join(tempdir, 'output.txt')

    script_path = File.join(tempdir, 'shift_test.sh')
    File.write(script_path, <<~SCRIPT)
      echo $1 >> #{output_file}
      shift
      echo $1 >> #{output_file}
      shift
      echo $1 >> #{output_file}
    SCRIPT

    execute("source #{script_path} first second third")

    assert_equal "first\nsecond\nthird\n", File.read(output_file)
  ensure
    FileUtils.rm_rf(tempdir)
  end
end
