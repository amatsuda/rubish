# frozen_string_literal: true

require_relative 'test_helper'

# ${var@Q} uses $'...' quoting when the value has control characters (bash)
class TestQuoteTransformControlChars < Test::Unit::TestCase
  def test_newline_and_tab
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', %q{y=$'a\nb'; echo "${y@Q}"; t=$'x\ty'; echo "${t@Q}"; p="it's"; echo "${p@Q}"}, err: File::NULL], &:read)
    assert_equal "$'a\\nb'\n$'x\\ty'\n'it'\\''s'\n", out
  end
end
