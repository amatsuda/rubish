# frozen_string_literal: true

require_relative 'test_helper'

# `declare -x` with no names lists inherited environment variables too
class TestDeclareXListsEnvironment < Test::Unit::TestCase
  def test_environment_listed
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen({ 'QX_FROM_ENV' => 'v' }, [exe, '-c', %q{declare -x | grep -c '^declare -x QX_FROM_ENV="v"$'}, err: %i[child out]], &:read)
    assert_equal "1\n", out
  end
end
