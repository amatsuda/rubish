# frozen_string_literal: true

require_relative 'test_helper'

# Brace expansion details: zero padding with negatives, escaped commas,
# quoted suffixes, and quoted parts around the braces
class TestBraceExpansionDetails < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_zero_padding_with_negative_numbers
    assert_equal "-05 000 005\n00 05 10\n", run_shell('echo {-05..05..5}; echo {00..10..5}')
  end

  def test_escaped_comma
    assert_equal "a,b c\n", run_shell('echo {a\,b,c}')
  end

  def test_ansi_c_quoted_suffix_is_kept
    assert_equal "a\n|b\n|", run_shell(%q{printf '%s|' {a,b}$'\n'})
  end

  def test_quoted_parts_around_the_braces
    assert_equal "abd acd\naf ag\nabd acd\n", run_shell(%q{echo "a"{b,c}"d"; x=a; echo "${x}"{f,g}; /bin/echo "a"{b,c}"d"})
  end
end
