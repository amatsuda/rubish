# frozen_string_literal: true

require_relative 'test_helper'

# A builtin with an output redirection must still run as the builtin (in the
# forked child), not be looked up as an external command
class TestBuiltinWithRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @dir = Dir.mktmpdir('rubish_builtin_redirect')
  end

  def teardown
    FileUtils.rm_rf(@dir)
    execute('unalias -a') rescue nil
  end

  def out
    File.join(@dir, 'out.txt')
  end

  def test_help_with_redirect
    capture_output { execute("help cd > #{out}") }
    assert_equal 0, @repl.instance_variable_get(:@last_status)
    assert_match(/Change the current directory/, File.read(out))
  end

  def test_type_with_redirect
    execute("type cd > #{out}")
    assert_match(/shell builtin/, File.read(out))
  end

  def test_alias_listing_with_redirect
    execute('alias rubish_t=echo')
    execute("alias > #{out}")
    assert_match(/rubish_t/, File.read(out))
  end

  def test_builtin_with_stderr_redirect_only
    err = File.join(@dir, 'err.txt')
    capture_output { execute("printf '%d' abc 2> #{err}") }
    assert_match(/invalid number/, File.read(err))
  end

  def test_builtin_redirect_exit_status
    capture_output { execute("type no_such_cmd_rubish_zz > #{out} 2>&1") }
    assert_equal 1, @repl.instance_variable_get(:@last_status)
  end
end
