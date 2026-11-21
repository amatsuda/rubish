# frozen_string_literal: true

require_relative 'test_helper'

# The -C callback runs with mapfile's redirections in effect, so
# `mapfile -C cb ... > /dev/null` keeps the callback's output quiet too
class TestMapfileCallbackRedirect < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_callback_output_follows_the_redirect
    out = capture_stdout { execute(%q(mapfile -t -C 'echo cb' -c 1 lines_mcb <<< $'a\nb' > /dev/null; echo "${#lines_mcb[@]}")) }
    assert_equal "2\n", out
  end

  def test_callback_runs_without_redirect
    out = capture_stdout { execute(%q(mapfile -t -C 'echo cb' -c 1 lines_mcb2 <<< $'a\nb')) }
    assert_equal "cb 0 a\ncb 1 b\n", out
  end
end
