# frozen_string_literal: true

require_relative 'test_helper'

# `[[ -o optname ]]` tests a shell option
class TestCondOptionTest < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('set +e; set -B')
  end

  def test_set_o_options
    out = capture_stdout { execute('[[ -o errexit ]]; echo $?; set -e; [[ -o errexit ]]; echo $?; set +e; [[ -o nosuch ]]; echo $?') }
    assert_equal "1\n0\n1\n", out
  end

  def test_short_options_by_long_name
    out = capture_stdout { execute('[[ -o braceexpand ]] && echo b; set +B; [[ -o braceexpand ]] || echo nb; set -B') }
    assert_equal "b\nnb\n", out
  end
end
