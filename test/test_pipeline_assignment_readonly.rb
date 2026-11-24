# frozen_string_literal: true

require_relative 'test_helper'

# An assignment that is a pipeline element still reports a readonly variable
class TestPipelineAssignmentReadonly < Test::Unit::TestCase
  def test_messages
    exe = File.expand_path('../exe/rubish', __dir__)
    out = IO.popen([exe, '-c', 'readonly -a ra=(1 2); ra[0]=9 2>&1 | head -1; declare -ri n=5; n=6 2>&1 | head -1; echo "$n ${ra[0]}"', err: %i[child out]], &:read)
    assert_equal "rubish: ra: readonly variable\nrubish: n: readonly variable\n5 1\n", out
  end
end
