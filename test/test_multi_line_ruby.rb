# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'

# Multi-line inline-Ruby support in execute() and in source(). Lets users
# put `Reline::Face.config(:completion_dialog) do |c| … end` style blocks
# in rubishrc without one-liner reformatting.
class MultiLineRubyTest < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    Rubish::Builtins.current_state = @repl.instance_variable_get(:@state)
    # Reline::Face is global state — reset between tests
    Reline::Face.reset_to_initial_configs
  end

  def teardown
    Reline::Face.reset_to_initial_configs
  end

  class FakeFrontend
    def initialize(continuation_lines = [])
      @lines = continuation_lines.dup
      @asked = []
    end
    attr_reader :asked
    def read_continuation_line(_prompt)
      @asked << :asked
      @lines.shift
    end
    def read_line(*); nil; end
    def read_simple_line(*); nil; end
    def insert_text(_text); end
    def setup_completion(&_blk); end
  end

  # ----- ruby_input_incomplete? helper ----------------------------------

  def test_incomplete_detection_unexpected_end_of_input
    assert @repl.send(:ruby_input_incomplete?, "syntax error, unexpected end-of-input, expecting `end'")
  end

  def test_incomplete_detection_unterminated_string
    assert @repl.send(:ruby_input_incomplete?, "unterminated string meets end of file")
  end

  def test_incomplete_detection_false_on_real_syntax_error
    refute @repl.send(:ruby_input_incomplete?, "syntax error, unexpected '}'")
  end

  # ----- interactive REPL path: execute() prompts for continuation -----

  def test_interactive_multi_line_block_collects_via_frontend
    fake = FakeFrontend.new([
      'conf.define :default,  foreground: :cyan,  background: :black',
      'conf.define :enhanced, foreground: :black, background: :cyan',
      'end',
    ])
    @repl.instance_variable_set(:@frontend, fake)

    @repl.send(:execute, 'Reline::Face.config(:completion_dialog) do |conf|')

    assert_match(/36/, Reline::Face[:completion_dialog][:default])   # cyan
    assert_match(/40/, Reline::Face[:completion_dialog][:default])   # bg black
    assert_match(/30/, Reline::Face[:completion_dialog][:enhanced])  # black
    assert_match(/46/, Reline::Face[:completion_dialog][:enhanced])  # bg cyan
    assert_equal 3, fake.asked.length  # collected exactly 3 continuation lines
  end

  def test_interactive_real_syntax_error_does_not_loop
    fake = FakeFrontend.new([])  # no lines available
    @repl.instance_variable_set(:@frontend, fake)

    # Mismatched bracket: real syntax error, not "incomplete"
    @repl.send(:execute, 'Time.now.}')

    # Must NOT have called read_continuation_line at all
    assert_empty fake.asked
  end

  def test_interactive_eof_during_continuation_returns_cleanly
    fake = FakeFrontend.new([])  # frontend returns nil on first ask
    @repl.instance_variable_set(:@frontend, fake)

    # This is incomplete — but the frontend has nothing more to give.
    # The REPL should bail out (set last_status = 1) without raising.
    assert_nothing_raised do
      @repl.send(:execute, 'Reline::Face.config(:completion_dialog) do |conf|')
    end
  end

  def test_interactive_lambda_multi_line
    fake = FakeFrontend.new(['  2 ** 10', '}.call'])
    @repl.instance_variable_set(:@frontend, fake)

    # Lambda literal split across lines; the auto_call_lambda path runs
    # the resulting Proc since it has arity 0. We don't assert output
    # here (it's just `p`d), only that nothing raises.
    assert_nothing_raised do
      @repl.send(:execute, '-> {')
    end
  end

  # ----- source() path: rcfile accumulation ----------------------------

  def test_source_accumulates_multi_line_ruby_block
    Tempfile.create(['rubishrc', '.rb']) do |t|
      t.write(<<~RUBY)
        Reline::Face.config(:completion_dialog) do |conf|
          conf.define :default,  foreground: :cyan,  background: :black
          conf.define :enhanced, foreground: :black, background: :cyan, style: :bold
          conf.define :scrollbar, foreground: :white, background: :black
        end
      RUBY
      t.flush

      capture_stdout { Rubish::Builtins.run('source', [t.path]) }
    end

    assert_match(/36/, Reline::Face[:completion_dialog][:default])
    assert_match(/40/, Reline::Face[:completion_dialog][:default])
    assert_match(/30/, Reline::Face[:completion_dialog][:enhanced])
    assert_match(/46/, Reline::Face[:completion_dialog][:enhanced])
    assert_match(/;1m\z/, Reline::Face[:completion_dialog][:enhanced])  # bold
    assert_match(/37/, Reline::Face[:completion_dialog][:scrollbar])
  end

  def test_source_mixes_shell_lines_around_ruby_block
    Tempfile.create(['rubishrc', '.rb']) do |t|
      t.write(<<~RUBY)
        # comment
        export RUBISH_TEST_MULTILINE_BEFORE=1

        Reline::Face.config(:completion_dialog) do |conf|
          conf.define :default, foreground: :red
        end

        export RUBISH_TEST_MULTILINE_AFTER=1
      RUBY
      t.flush

      capture_stdout { Rubish::Builtins.run('source', [t.path]) }
    end

    assert_equal '1', ENV['RUBISH_TEST_MULTILINE_BEFORE']
    assert_equal '1', ENV['RUBISH_TEST_MULTILINE_AFTER']
    assert_match(/31/, Reline::Face[:completion_dialog][:default])  # red
  ensure
    ENV.delete('RUBISH_TEST_MULTILINE_BEFORE')
    ENV.delete('RUBISH_TEST_MULTILINE_AFTER')
  end

  def test_source_does_not_misidentify_uppercase_variable_assignment
    # `RUBISH_TEST_ASSIGN=foo` matches the [A-Z] prefix but is a shell
    # var assignment, not Ruby. Must NOT go through the Ruby accumulator.
    Tempfile.create(['rubishrc', '.rb']) do |t|
      t.write(<<~SHELL)
        RUBISH_TEST_ASSIGN=42
        export RUBISH_TEST_ASSIGN
      SHELL
      t.flush

      capture_stdout { Rubish::Builtins.run('source', [t.path]) }
    end

    assert_equal '42', ENV['RUBISH_TEST_ASSIGN']
  ensure
    ENV.delete('RUBISH_TEST_ASSIGN')
  end

  # ----- ruby_input_incomplete_ast? helper -----------------------------

  def test_incomplete_ast_detects_open_do_block
    ctx = Rubish::Builtins.context
    assert ctx.send(:ruby_input_incomplete_ast?, 'Reline::Face.config(:x) do |c|')
  end

  def test_incomplete_ast_passes_on_real_syntax_error
    ctx = Rubish::Builtins.context
    refute ctx.send(:ruby_input_incomplete_ast?, 'Time.now.}')
  end

  def test_incomplete_ast_false_on_complete_code
    ctx = Rubish::Builtins.context
    refute ctx.send(:ruby_input_incomplete_ast?, 'Time.now')
    refute ctx.send(:ruby_input_incomplete_ast?, "Reline::Face.config(:x) { |c| c.define :default, foreground: :red }")
  end

  def test_source_does_not_p_block_result
    Tempfile.create(['rubishrc', '.rb']) do |t|
      t.write(<<~RUBY)
        Reline::Face.config(:completion_dialog) do |conf|
          conf.define :default, foreground: :cyan
        end
        Time.now.year
      RUBY
      t.flush

      out = capture_stdout { Rubish::Builtins.run('source', [t.path]) }
      # No Config object dump, no integer year
      refute_match(/Reline::Face::Config/, out)
      refute_match(/\b20\d{2}\b/, out)
    end
  end

  def test_interactive_multi_line_block_does_not_p_result
    fake = FakeFrontend.new([
      'conf.define :default, foreground: :red',
      'end',
    ])
    @repl.instance_variable_set(:@frontend, fake)

    out = capture_stdout do
      @repl.send(:execute, 'Reline::Face.config(:completion_dialog) do |conf|')
    end
    refute_match(/Reline::Face::Config/, out)
  end

  def test_interactive_single_line_still_prints_result
    # Plain `Time.now` typed at the REPL should still print its value —
    # that's the IRB-style read-eval-PRINT-loop UX. We only suppress p
    # for multi-line blocks and sourced files.
    out = capture_stdout do
      @repl.send(:execute, '1 + 2 + 3')  # avoid timestamp drift
    end
    # Wait, 1+2+3 starts with `1` not capital — wouldn't go through the
    # Ruby path. Use Math::PI which starts with capital.
    out2 = capture_stdout do
      @repl.send(:execute, 'Math::PI.round(2)')
    end
    assert_match(/3\.14/, out2)
  end

  def test_ruby_block_start_line_recognizes_constant_lines
    ctx = Rubish::Builtins.context
    assert ctx.send(:ruby_block_start_line?, 'Reline::Face.config(:foo) do |c|')
    assert ctx.send(:ruby_block_start_line?, '-> { 42 }')
    refute ctx.send(:ruby_block_start_line?, 'echo hi')
    refute ctx.send(:ruby_block_start_line?, 'FOO=42'),       'uppercase assignment is not Ruby'
    refute ctx.send(:ruby_block_start_line?, 'FOO[0]=42'),    'uppercase array assign is not Ruby'
  end

  private

  def capture_stdout
    require 'stringio'
    old, $stdout = $stdout, StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
