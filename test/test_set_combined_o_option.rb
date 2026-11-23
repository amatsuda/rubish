# frozen_string_literal: true

require_relative 'test_helper'

# `set -eo pipefail`: `o` may end a cluster of short options and take the
# following word as its option name
class TestSetCombinedOOption < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
  end

  def teardown
    execute('set +e +o pipefail')
  end

  def test_cluster_ending_in_o_takes_the_next_word
    out = capture_stdout { execute('set -eo pipefail; set -o') }
    assert_match(/^errexit\s+on$/, out)
    assert_match(/^pipefail\s+on$/, out)
  end

  def test_plus_cluster_ending_in_o
    out = capture_stdout { execute('set -e -o pipefail; set +eo pipefail; set -o') }
    assert_match(/^errexit\s+off$/, out)
    assert_match(/^pipefail\s+off$/, out)
  end
end
