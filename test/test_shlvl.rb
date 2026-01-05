# frozen_string_literal: true

require_relative 'test_helper'

class TestSHLVL < Test::Unit::TestCase
  def setup
    @original_env = ENV.to_h.dup
    @original_dir = Dir.pwd
    @tempdir = Dir.mktmpdir('rubish_shlvl_test')
    Dir.chdir(@tempdir)
    # Reset SHLVL to a known state before each test
    ENV.delete('SHLVL')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def execute(repl, line)
    repl.send(:execute, line)
  end

  # Basic SHLVL functionality

  def test_shlvl_starts_at_one
    repl = Rubish::REPL.new
    assert_equal '1', ENV['SHLVL']
  end

  def test_shlvl_increments_for_nested_shell
    repl1 = Rubish::REPL.new
    assert_equal '1', ENV['SHLVL']

    repl2 = Rubish::REPL.new
    assert_equal '2', ENV['SHLVL']

    repl3 = Rubish::REPL.new
    assert_equal '3', ENV['SHLVL']
  end

  def test_shlvl_inherits_from_environment
    ENV['SHLVL'] = '5'
    repl = Rubish::REPL.new
    assert_equal '6', ENV['SHLVL']
  end

  def test_shlvl_variable_expansion
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo $SHLVL > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1', value
  end

  def test_shlvl_braced_expansion
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo ${SHLVL} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1', value
  end

  def test_shlvl_double_quoted
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo \"Level: $SHLVL\" > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'Level: 1', content
  end

  # Setting SHLVL

  def test_set_shlvl
    repl = Rubish::REPL.new
    execute(repl, 'SHLVL=10')
    assert_equal '10', ENV['SHLVL']
  end

  def test_shlvl_persists_in_env
    repl = Rubish::REPL.new
    execute(repl, 'SHLVL=42')
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo $SHLVL > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '42', value
  end

  # Parameter expansion with SHLVL

  def test_shlvl_with_default_expansion
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo ${SHLVL:-default} > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1', value
  end

  def test_shlvl_with_alternate_expansion
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo ${SHLVL:+set} > #{output_file}")
    content = File.read(output_file).strip
    assert_equal 'set', content, 'SHLVL should be considered set'
  end

  # Arithmetic with SHLVL

  def test_shlvl_in_arithmetic
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "echo $((SHLVL + 5)) > #{output_file}")
    value = File.read(output_file).strip.to_i
    assert_equal 6, value
  end

  # Edge cases

  def test_shlvl_handles_non_numeric
    ENV['SHLVL'] = 'invalid'
    repl = Rubish::REPL.new
    # to_i on 'invalid' returns 0, so SHLVL becomes 1
    assert_equal '1', ENV['SHLVL']
  end

  def test_shlvl_handles_negative
    ENV['SHLVL'] = '-5'
    repl = Rubish::REPL.new
    # -5 + 1 = -4
    assert_equal '-4', ENV['SHLVL']
  end

  def test_shlvl_handles_empty
    ENV['SHLVL'] = ''
    repl = Rubish::REPL.new
    # '' to_i is 0, so SHLVL becomes 1
    assert_equal '1', ENV['SHLVL']
  end

  def test_shlvl_in_subshell
    repl = Rubish::REPL.new
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "(echo $SHLVL) > #{output_file}")
    value = File.read(output_file).strip
    # Subshell inherits parent's SHLVL (doesn't increment for subshell)
    assert_equal '1', value
  end

  def test_shlvl_export
    repl = Rubish::REPL.new
    # SHLVL should be visible to child processes
    output_file = File.join(@tempdir, 'output.txt')
    execute(repl, "ruby -e 'puts ENV[\"SHLVL\"]' > #{output_file}")
    value = File.read(output_file).strip
    assert_equal '1', value
  end
end
