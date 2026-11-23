# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# The function definition forms bash accepts: `function name` with or
# without `()`, any compound command as the body, and redirections on the
# body that apply to every call
class TestFunctionDefinitionForms < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_function_keyword_with_parens
    out = capture_stdout { execute('function g() { echo both; }; g') }
    assert_equal "both\n", out
  end

  def test_function_keyword_without_parens
    out = capture_stdout { execute('function f { echo brace; }; f') }
    assert_equal "brace\n", out
  end

  def test_subshell_body_runs_in_a_subshell
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'f() ( echo subfn; x=changed ); x=orig; f; echo $x'], &:read)
    assert_equal "subfn\norig\n", out
  end

  def test_if_body
    out = capture_stdout { execute('f() if true; then echo iffn; fi; f') }
    assert_equal "iffn\n", out
  end

  def test_for_body
    out = capture_stdout { execute('f() for i in 1 2; do echo $i; done; f') }
    assert_equal "1\n2\n", out
  end

  def test_redirection_on_the_body_applies_to_each_call
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out')
      execute("f() { echo fn; } > #{out}; f; f")
      assert_equal "fn\n", File.read(out)
    end
  end
end
