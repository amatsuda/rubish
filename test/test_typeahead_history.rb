# frozen_string_literal: true

require_relative 'test_helper'

# A command typed while the previous one was still running is executed from
# the typeahead queue; it must reach history like any other command
class TestTypeaheadHistory < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @saved = Reline::HISTORY.to_a
    Reline::HISTORY.clear
  end

  def teardown
    Reline::HISTORY.clear
    @saved.each { |h| Reline::HISTORY.push(h) }
  end

  def test_queued_command_is_added_to_history
    @repl.instance_variable_set(:@pending_commands, ['echo typed_ahead'])
    out = capture_stdout { @repl.send(:process_line) }
    assert_match(/typed_ahead/, out)
    assert_equal 'echo typed_ahead', Reline::HISTORY.to_a.last
  end
end
