# frozen_string_literal: true

require_relative 'test_helper'

class TestReturn < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @tempdir = Dir.mktmpdir('rubish_return_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
  end

  def create_script(name, content)
    path = File.join(@tempdir, name)
    File.write(path, content)
    path
  end

  def test_return_is_builtin
    assert Rubish::Builtins.builtin?('return')
  end

  def test_return_exits_script_early
    output_file = File.join(@tempdir, 'output.txt')
    script = create_script('early_return.sh', <<~SCRIPT)
      echo before > #{output_file}
      return
      echo after >> #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "before\n", File.read(output_file)
  end

  def test_return_with_zero_code
    output_file = File.join(@tempdir, 'output.txt')
    script = create_script('return_zero.sh', <<~SCRIPT)
      echo done > #{output_file}
      return 0
      echo never >> #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "done\n", File.read(output_file)
  end

  def test_return_with_nonzero_code
    output_file = File.join(@tempdir, 'output.txt')
    script = create_script('return_error.sh', <<~SCRIPT)
      echo error > #{output_file}
      return 1
      echo never >> #{output_file}
    SCRIPT

    execute("source #{script}")

    assert_equal "error\n", File.read(output_file)
  end

  def test_return_in_middle_of_script
    output_file = File.join(@tempdir, 'output.txt')
    script = create_script('middle_return.sh', <<~SCRIPT)
      echo first > #{output_file}
      echo second >> #{output_file}
      return
      echo third >> #{output_file}
    SCRIPT

    execute("source #{script}")

    content = File.read(output_file)
    assert_match(/first/, content)
    assert_match(/second/, content)
    assert_no_match(/third/, content)
  end

  def test_return_restores_positional_params
    @repl.positional_params = %w[original]
    script = create_script('params.sh', <<~SCRIPT)
      set -- new params
      return
    SCRIPT

    execute("source #{script}")

    assert_equal %w[original], @repl.positional_params
  end

  def test_return_restores_script_name
    script = create_script('name.sh', <<~SCRIPT)
      return
    SCRIPT

    execute("source #{script}")

    assert_equal 'rubish', @repl.script_name
  end

  def test_nested_script_return
    output_file = File.join(@tempdir, 'output.txt')

    inner_script = create_script('inner.sh', <<~SCRIPT)
      echo inner >> #{output_file}
      return
      echo inner_after >> #{output_file}
    SCRIPT

    outer_script = create_script('outer.sh', <<~SCRIPT)
      echo outer_before >> #{output_file}
      source #{inner_script}
      echo outer_after >> #{output_file}
    SCRIPT

    execute("source #{outer_script}")

    content = File.read(output_file)
    assert_match(/outer_before/, content)
    assert_match(/inner/, content)
    assert_match(/outer_after/, content)
    assert_no_match(/inner_after/, content)
  end
end
