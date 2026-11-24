# frozen_string_literal: true

require_relative 'test_helper'

# A subshell can be the condition of if, while and until
class TestSubshellCondition < Test::Unit::TestCase
  def test_if_and_while
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'if (true); then echo t; fi; if (false); then :; else echo f; fi; while (false); do :; done; echo w', err: %i[child out]], &:read)
    assert_equal "t\nf\nw\n", out
  end
end
