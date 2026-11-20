# frozen_string_literal: true

require_relative 'test_helper'

# $- lists the current option flags; ${!prefix*} / ${!prefix@} list variable
# names starting with prefix
class TestDollarDashAndPrefixNames < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('RUBISH_PFX_ONE=1; RUBISH_PFX_TWO=2')
  end

  def teardown
    Rubish::Builtins.unset(%w[RUBISH_PFX_ONE RUBISH_PFX_TWO])
    execute('set +e')
  end

  def echo(expr, list: false)
    capture_stdout { execute("#{list ? 'true; ' : ''}echo \"#{expr}\"") }.chomp
  end

  def test_dollar_dash_reflects_set_options
    execute('set -e')
    assert_match(/e/, echo('$-'))
    assert_match(/e/, echo('${-}'))
    assert_match(/e/, echo('$-', list: true))
  end

  def test_dollar_dash_is_not_literal
    assert_no_match(/\$/, echo('$-'))
  end

  def test_prefix_names_star_joins_sorted_names
    assert_equal 'RUBISH_PFX_ONE RUBISH_PFX_TWO', echo('${!RUBISH_PFX_*}')
    assert_equal 'RUBISH_PFX_ONE RUBISH_PFX_TWO', echo('${!RUBISH_PFX_*}', list: true)
  end

  def test_prefix_names_at_gives_separate_words
    out = capture_stdout { execute('printf "[%s]" "${!RUBISH_PFX_@}"; echo') }
    assert_equal "[RUBISH_PFX_ONE][RUBISH_PFX_TWO]\n", out
  end

  def test_prefix_names_include_environment_variables
    assert_match(/\bHOME\b/, echo('${!HO*}'))
  end

  def test_prefix_without_matches_is_empty
    assert_equal '', echo('${!NO_SUCH_PREFIX_RUBISH*}')
  end
end
