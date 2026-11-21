# frozen_string_literal: true

require_relative 'test_helper'

# set -x traces each simple command as it runs, after expansion, quoting
# words that need it, so a trace enabled mid-line takes effect at once
class TestXtracePerCommand < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    ENV.delete('PS4')
  end

  def teardown
    execute('set +x')
  end

  def test_trace_enabled_within_a_list
    err = capture_stderr { capture_stdout { execute('set -x; echo traced; x="a b"; echo "$x" ""; set +x; echo done') } }
    assert_equal "+ echo traced\n+ x='a b'\n+ echo 'a b' ''\n+ set +x\n", err
  end

  def test_trace_shows_expanded_words_once
    execute('xt_v=hello')
    err = capture_stderr { capture_stdout { execute('set -x') ; execute('echo $xt_v') } }
    assert_equal "+ echo hello\n", err
  end
end
