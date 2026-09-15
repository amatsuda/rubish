# frozen_string_literal: true

require_relative 'test_helper'

# Brace group compound command: { list; } runs in the current shell.
# `brew shellenv` emits `[ -z "${MANPATH-}" ] || { export ...; };` which
# used to fail with "Unknown AST node: NilClass".
class TestBraceGroup < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_brace_group_test')
  end

  def teardown
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def output_file
    File.join(@tempdir, 'output.txt')
  end

  def test_brace_group_runs_commands
    output = capture_output { execute('{ echo one; echo two; }') }
    assert_equal "one\ntwo\n", output
  end

  def test_brace_group_runs_in_current_shell
    execute('{ BRACE_VAR=inside; }')
    assert_equal 'inside', get_shell_var('BRACE_VAR')
  ensure
    Rubish::Builtins.delete_var('BRACE_VAR')
  end

  def test_brace_group_as_or_right_operand
    output = capture_output { execute('false || { echo reached; };') }
    assert_equal "reached\n", output
  end

  def test_brace_group_as_or_right_operand_not_run_when_left_succeeds
    output = capture_output { execute('true || { echo reached; };') }
    assert_equal '', output
  end

  def test_brace_group_as_and_right_operand
    output = capture_output { execute('true && { echo reached; }') }
    assert_equal "reached\n", output
  end

  def test_brace_group_with_redirect
    execute("{ echo one; echo two; } > #{output_file}")
    assert_equal "one\ntwo\n", File.read(output_file)
  end

  def test_brew_shellenv_manpath_line
    ENV['BREW_TEST_MANPATH'] = 'a:b'
    execute('[ -z "${BREW_TEST_MANPATH-}" ] || { export BREW_TEST_MANPATH="${BREW_TEST_MANPATH}:extra"; };')
    assert_equal 'a:b:extra', ENV['BREW_TEST_MANPATH']
  end
end
