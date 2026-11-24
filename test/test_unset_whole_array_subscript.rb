# frozen_string_literal: true

require_relative 'test_helper'

# `unset a[@]` and `unset a[*]` remove the whole array
class TestUnsetWholeArraySubscript < Test::Unit::TestCase
  def run_shell(script)
    exe = File.expand_path('../exe/rubish', __dir__)
    IO.popen([exe, '-c', script, err: %i[child out]], &:read)
  end

  def test_at_subscript
    assert_equal "[] 0\n", run_shell('a=(1 2 3); unset a[@]; echo "[${a[@]}] ${#a[@]}"')
  end

  def test_star_subscript
    assert_equal "0 unset\n", run_shell(%q{b=(1 2 3); unset 'b[*]'; echo "${#b[@]} ${b-unset}"})
  end
end
