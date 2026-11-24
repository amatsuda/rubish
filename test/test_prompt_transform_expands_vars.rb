# frozen_string_literal: true

require_relative 'test_helper'

# ${y@P} expands the value as a prompt, parameter expansion included (promptvars)
class TestPromptTransformExpandsVars < Test::Unit::TestCase
  def test_promptvars
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{x=' a b '; y='$x'; echo "[${y@P}]"; shopt -u promptvars; echo "[${y@P}]"}, err: %i[child out]], &:read)
    assert_equal "[ a b ]\n[$x]\n", out
  end
end
