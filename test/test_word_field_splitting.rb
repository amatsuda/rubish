# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# An unquoted expansion inside a larger word is split into fields, as bash
# splits it, while the word's literal and quoted text is not: X$(echo "a b")Y
# is the two words Xa and bY
class TestWordFieldSplitting < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir('rubish_field_split') do |dir|
      File.write(File.join(dir, 'g1'), '')
      File.write(File.join(dir, 'g2'), '')
      IO.popen([exe, '--norc', '-c', script, chdir: dir, err: %i[child out]], &:read)
    end
  end

  def test_braced_variable_inside_a_word
    assert_equal "<Xa><bY>\n", run_shell(%q{x="a b"; true; printf "<%s>" X${x}Y; echo})
  end

  def test_variable_at_the_end_of_a_word
    assert_equal "<Xa><b>\n", run_shell(%q{x="a b"; true; printf "<%s>" X$x; echo})
  end

  def test_dollar_paren_inside_a_word
    assert_equal "<Xa><bY>\n", run_shell(%q{true; printf "<%s>" X$(echo "a b")Y; echo})
  end

  def test_backtick_inside_a_word
    assert_equal "<Xa><bY>\n", run_shell(%q{true; printf "<%s>" X`echo "a b"`Y; echo})
  end

  def test_leading_and_trailing_blanks_break_the_word
    assert_equal "<X><a><b><Y>\n", run_shell(%q{true; printf "<%s>" X$(echo " a b ")Y; echo})
  end

  def test_two_adjacent_substitutions
    assert_equal "<a><bc><d>\n", run_shell(%q{true; printf "<%s>" $(echo "a b")$(echo "c d"); echo})
  end

  def test_empty_substitution_leaves_the_literal_text
    assert_equal "<XY>\n", run_shell(%q{true; printf "<%s>" X$(true)Y; echo})
  end

  def test_empty_unquoted_expansions_vanish
    assert_equal "<.>\n", run_shell(%q{x=""; true; printf "<%s>" $x$x .; echo})
  end

  def test_quoted_empty_part_keeps_an_empty_word
    assert_equal "<><.>\n", run_shell(%q{x=""; true; printf "<%s>" ""$x .; echo})
  end

  def test_quoted_word_is_not_split
    assert_equal "<Xa bY>\n", run_shell(%q{true; printf "<%s>" "X$(echo "a b")Y"; echo})
  end

  def test_quoted_part_is_not_split
    assert_equal "<p qa><b>\n", run_shell(%q{x="a b"; true; printf "<%s>" "p q"$x; echo})
  end

  def test_split_words_are_globbed
    assert_equal "<X1><g1><g2>\n", run_shell(%q{x="1 g*"; true; printf "<%s>" X$x; echo})
  end

  def test_quoted_glob_character_stays_literal
    assert_equal "<*><g1><g2>\n", run_shell(%q{x=" g*"; true; printf "<%s>" "*"$x; echo})
  end

  def test_non_whitespace_ifs_delimits_each_field
    assert_equal "<Xa><b><><cY>\n", run_shell(%q{x="a:b::c"; IFS=:; true; printf "<%s>" X${x}Y; echo})
  end

  def test_whitespace_around_a_non_whitespace_delimiter
    assert_equal "<Xa><bY>\n", run_shell(%q{x="a : b"; IFS=" :"; true; printf "<%s>" X${x}Y; echo})
  end

  def test_empty_ifs_does_not_split
    assert_equal "<Xa bY>\n", run_shell(%q{x="a b"; IFS=; true; printf "<%s>" X${x}Y; echo})
  end

  def test_assignment_argument_of_export_is_not_split
    assert_equal "<Xa b>\n", run_shell(%q{x="a b"; export A=X$x; printf "<%s>" "$A"; echo})
  end

  def test_for_word_list_splits_inside_a_word
    assert_equal "<Xa><bY>\n", run_shell(%q{x="a b"; for w in X${x}Y; do printf "<%s>" "$w"; done; echo})
  end

  def test_lone_command_splits_inside_a_word
    assert_equal "<Xa><b>\n", run_shell(%q{x="a b"; printf "<%s>" X$x; echo})
  end
  def test_split_word_in_the_middle_is_globbed
    assert_equal "<X1><g1><g2><2>\n", run_shell(%q{x="1 g* 2"; true; printf "<%s>" X$x; echo})
  end
end
