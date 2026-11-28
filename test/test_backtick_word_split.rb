# frozen_string_literal: true

require_relative 'test_helper'

# An unquoted backtick word is expanded wherever it stands, and its output is
# split into words, as bash splits it
class TestBacktickWordSplit < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '--norc', '-c', script, err: %i[child out]], &:read)
  end

  def test_slash_inside_the_backticks_after_a_separator
    # a word with a slash looked like a path and was handed to the glob, which
    # left the backticks in it
    assert_equal "</a>\n", run_shell(%q{f() { printf "<%s>" "$@"; echo; }; true; f `echo "/a"`})
  end

  def test_output_is_split_into_words
    assert_equal "3 <a> <b> <c>\n", run_shell(%q{set -- `echo "a b c"`; echo "$# <$1> <$2> <$3>"})
  end

  def test_quoted_backticks_stay_one_word
    assert_equal "1 <a b c>\n", run_shell(%q{set -- "`echo "a b c"`"; echo "$# <$1>"})
  end

  def test_eval_of_an_assignment_with_a_path
    # /etc/profile's `eval `/usr/libexec/path_helper -s``
    assert_equal "/a/b\n", run_shell(%q{eval `echo "P=/a/b; export P;"`; echo "$P"})
  end
end
