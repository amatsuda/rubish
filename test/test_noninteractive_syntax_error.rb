# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# Syntax errors in `rubish -c` and in scripts are reported as "rubish:
# syntax error ..." with status 2, never as a Ruby traceback, and never by
# prompting for continuation lines
class TestNoninteractiveSyntaxError < Test::Unit::TestCase
  EXE = File.expand_path('../exe/rubish', __dir__)
  LIB = File.expand_path('../lib', __dir__)

  def run_rubish(*args)
    out = IO.popen([RbConfig.ruby, '-I', LIB, EXE, *args], in: File::NULL, err: %i[child out], &:read)
    [out.gsub(/\e\[[0-9;?]*[A-Za-z]/, ''), $?.exitstatus]
  end

  def test_incomplete_command_is_a_syntax_error_not_a_prompt
    out, status = run_rubish('-c', 'if')
    assert_match(/rubish: -c: line \d+: syntax error: unexpected end of file/, out) # bash's wording
    assert_no_match(/^> /, out)
    assert_equal 2, status
  end

  def test_unexpected_token_is_a_syntax_error
    out, status = run_rubish('-c', 'echo )')
    assert_match(/rubish: -c: line 1: syntax error near unexpected token `\)'/, out)
    assert_equal 2, status
  end

  def test_parser_error_has_no_traceback
    out, status = run_rubish('-c', 'case x in *.@(a)) echo;; esac')
    assert_match(/\Arubish: /, out)
    assert_no_match(/parser\.rb/, out)
    assert_equal 2, status
  end

  def test_script_with_unterminated_structure_exits_2
    Dir.mktmpdir('rubish_syn') do |dir|
      script = File.join(dir, 's.sh')
      File.write(script, "echo one\nif\n")
      out, status = run_rubish(script)
      assert_match(/^one$/, out)
      assert_match(/syntax error/, out)
      assert_equal 2, status
    end
  end

  def test_execute_reports_leftover_token_with_status_2
    repl = Rubish::REPL.new
    error = assert_raise(Rubish::ShellSyntaxError) { repl.send(:execute, 'echo )') }
    assert_match(/syntax error near unexpected token/, error.message)
    assert_equal 2, repl.instance_variable_get(:@last_status)
  end
end
