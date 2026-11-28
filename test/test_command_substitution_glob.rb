# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

# The words an unquoted command substitution splits into are patterns, as
# bash expands them: `$(echo "g*")` lists the matching files
class TestCommandSubstitutionGlob < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    Dir.mktmpdir('rubish_subst_glob') do |dir|
      File.write(File.join(dir, 'g1'), '')
      File.write(File.join(dir, 'g2'), '')
      IO.popen([exe, '--norc', '-c', script, chdir: dir, err: %i[child out]], &:read)
    end
  end

  def test_dollar_paren_output_is_globbed_on_its_own
    assert_equal "<g1><g2>\n", run_shell(%q{printf "<%s>" $(echo "g*"); echo})
  end

  def test_dollar_paren_output_is_globbed_after_a_separator
    assert_equal "<g1><g2>\n", run_shell(%q{true; printf "<%s>" $(echo "g*"); echo})
  end

  def test_backtick_output_is_globbed
    assert_equal "<g1><g2>\n", run_shell(%q{true; printf "<%s>" `echo "g*"`; echo})
  end

  def test_for_word_list_globs_substitution_output
    assert_equal "<g1><g2>\n", run_shell(%q{for w in $(echo "g*"); do printf "<%s>" "$w"; done; echo})
  end

  def test_quoted_substitution_is_not_globbed
    assert_equal "<g*>\n", run_shell(%q{true; printf "<%s>" "$(echo "g*")"; echo})
  end

  def test_noglob_keeps_the_pattern
    assert_equal "<g*>\n", run_shell(%q{set -f; true; printf "<%s>" $(echo "g*"); echo})
  end

  def test_nullglob_drops_an_unmatched_pattern
    assert_equal "<.>\n", run_shell(%q{shopt -s nullglob; true; printf "<%s>" $(echo "zz*") .; echo})
  end
end
