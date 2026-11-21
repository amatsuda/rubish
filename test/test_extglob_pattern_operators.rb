# frozen_string_literal: true

require_relative 'test_helper'

# With extglob on, ${var##+( )} and friends take extended patterns
class TestExtglobPatternOperators < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    execute('shopt -s extglob')
  end

  def teardown
    execute('shopt -u extglob')
  end

  def test_trim_with_plus_group
    execute('s_eg="  trim  "')
    out = capture_stdout { execute('echo "[${s_eg##+( )}][${s_eg%%+( )}][${s_eg#+( )}]"; true') }
    assert_equal "[trim  ][  trim][ trim  ]\n", out
  end

  def test_replace_with_at_group
    execute('f_eg=photo.jpeg')
    out = capture_stdout { execute('echo "${f_eg/%@(jpg|jpeg)/png}" "${f_eg%.*(jpg|jpeg)}"; true') }
    assert_equal "photo.png photo\n", out
  end
end
