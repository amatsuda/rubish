# frozen_string_literal: true

require_relative 'test_helper'

# ${x#}, ${x%}, ${x##} and ${x%%} with an empty pattern leave the value as it is
class TestEmptyPatternRemoval < Test::Unit::TestCase
  def test_unchanged
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'x=abc; echo "[${x#}]" "[${x%}]" "[${x##}]" "[${x%%}]"; echo "[${x#a}]"', err: %i[child out]], &:read)
    assert_equal "[abc] [abc] [abc] [abc]\n[bc]\n", out
  end
end
