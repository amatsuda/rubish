# frozen_string_literal: true

require_relative 'test_helper'

# A herestring's word may hold command substitutions, expansions and quotes
class TestHerestringWordForms < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_substitution_and_expansion
    assert_equal "1  2\ndef\n", run_shell(%q{cat <<< $(echo '1  2'); cat <<< ${nosuch:-def}})
  end

  def test_partly_quoted_word
    assert_equal "ab c\n", run_shell(%q{cat <<< a"b c"})
  end
end
