# frozen_string_literal: true

require_relative 'test_helper'

class TestSet < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_set_is_builtin
    assert Rubish::Builtins.builtin?('set')
  end

  def test_set_with_double_dash
    execute('set -- a b c')
    assert_equal %w[a b c], @repl.positional_params
  end

  def test_set_without_double_dash
    execute('set x y z')
    assert_equal %w[x y z], @repl.positional_params
  end

  def test_set_clears_with_no_args
    @repl.positional_params = %w[old params]
    execute('set')
    assert_equal [], @repl.positional_params
  end

  def test_set_clears_with_double_dash_only
    @repl.positional_params = %w[old params]
    execute('set --')
    assert_equal [], @repl.positional_params
  end

  def test_set_replaces_existing_params
    @repl.positional_params = %w[old values]
    execute('set -- new ones here')
    assert_equal %w[new ones here], @repl.positional_params
  end

  def test_set_updates_special_vars
    execute('set -- first second third')

    result = @repl.send(:expand_single_arg, '$1')
    assert_equal 'first', result

    result = @repl.send(:expand_single_arg, '$#')
    assert_equal '3', result

    result = @repl.send(:expand_single_arg, '$@')
    assert_equal 'first second third', result
  end

  def test_set_single_param
    execute('set -- only')
    assert_equal ['only'], @repl.positional_params
  end

  def test_set_in_script
    tempdir = Dir.mktmpdir('rubish_set_test')
    output_file = File.join(tempdir, 'output.txt')

    script_path = File.join(tempdir, 'set_test.sh')
    File.write(script_path, <<~SCRIPT)
      set -- one two three
      echo $1 $2 $3 > #{output_file}
    SCRIPT

    execute("source #{script_path}")

    assert_equal "one two three\n", File.read(output_file)
  ensure
    FileUtils.rm_rf(tempdir)
  end

  def test_set_and_shift_together
    execute('set -- a b c d e')
    execute('shift 2')
    assert_equal %w[c d e], @repl.positional_params
  end
end
