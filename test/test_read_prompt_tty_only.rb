# frozen_string_literal: true

require_relative 'test_helper'

# `read -p prompt` shows the prompt only when input comes from a terminal,
# as bash does; a prompt written while reading from a pipe or here-string
# would end up in the output of scripts
class TestReadPromptTtyOnly < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def test_prompt_is_not_printed_when_stdin_is_not_a_terminal
    err = capture_stderr { execute("read -p 'name: ' v <<< val") }
    assert_equal '', err
    assert_equal 'val', get_shell_var('v')
  end
end
