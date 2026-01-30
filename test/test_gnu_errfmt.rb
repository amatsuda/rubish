# frozen_string_literal: true

require_relative 'test_helper'

class TestGnuErrfmt < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_shell_options = Rubish::Builtins.current_state.shell_options.dup
    @original_set_options = Rubish::Builtins.current_state.set_options.dup
  end

  def teardown
    Rubish::Builtins.current_state.shell_options.clear
    @original_shell_options.each { |k, v| Rubish::Builtins.current_state.shell_options[k] = v }
    Rubish::Builtins.current_state.set_options.clear
    @original_set_options.each { |k, v| Rubish::Builtins.current_state.set_options[k] = v }
  end

  # gnu_errfmt is disabled by default
  def test_gnu_errfmt_disabled_by_default
    assert_false Rubish::Builtins.shopt_enabled?('gnu_errfmt')
  end

  def test_gnu_errfmt_can_be_enabled
    execute('shopt -s gnu_errfmt')
    assert Rubish::Builtins.shopt_enabled?('gnu_errfmt')
  end

  def test_gnu_errfmt_can_be_disabled
    execute('shopt -s gnu_errfmt')
    execute('shopt -u gnu_errfmt')
    assert_false Rubish::Builtins.shopt_enabled?('gnu_errfmt')
  end

  # Test format_error without gnu_errfmt
  def test_format_error_standard_format
    msg = Rubish::Builtins.format_error('some error')
    assert_equal 'rubish: some error', msg
  end

  def test_format_error_standard_format_with_command
    msg = Rubish::Builtins.format_error('some error', command: 'mycommand')
    assert_equal 'rubish: mycommand: some error', msg
  end

  # Test format_error with gnu_errfmt enabled
  def test_format_error_gnu_format
    execute('shopt -s gnu_errfmt')

    msg = Rubish::Builtins.format_error('some error')
    # Should be in format: source:lineno: message
    assert_match(/\A\w+:\d+: some error\z/, msg)
  end

  def test_format_error_gnu_format_with_command
    execute('shopt -s gnu_errfmt')

    msg = Rubish::Builtins.format_error('some error', command: 'mycommand')
    # Should be in format: source:lineno: command: message
    assert_match(/\A\w+:\d+: mycommand: some error\z/, msg)
  end

  # Test that source file and line number are included
  def test_format_error_includes_source_and_lineno
    execute('shopt -s gnu_errfmt')

    # Get current source and lineno from the REPL
    source = @repl.instance_variable_get(:@current_source_file)
    lineno = @repl.instance_variable_get(:@lineno)

    msg = Rubish::Builtins.format_error('test error')
    assert_match(/\A#{Regexp.escape(source)}:#{lineno}: test error\z/, msg)
  end

  # Test shift error with gnu_errfmt
  def test_shift_error_gnu_format
    execute('shopt -s gnu_errfmt')
    execute('shopt -s shift_verbose')

    stderr = capture_stderr do
      # Try to shift more than available (no positional params)
      Rubish::Builtins.run('shift', ['100'])
    end

    # Should be in GNU format
    assert_match(/\A\w+:\d+: shift: shift count out of range\n\z/, stderr)
  end

  # Test shift error without gnu_errfmt (standard format)
  def test_shift_error_standard_format
    execute('shopt -s shift_verbose')

    stderr = capture_stderr do
      Rubish::Builtins.run('shift', ['100'])
    end

    # Should be in standard format
    assert_equal "rubish: shift: shift count out of range\n", stderr
  end

  # Test format_error produces correct output for unbound variable style errors
  def test_format_error_unbound_variable_style_gnu
    execute('shopt -s gnu_errfmt')

    msg = Rubish::Builtins.format_error('unbound variable', command: 'MY_VAR')
    assert_match(/\A\w+:\d+: MY_VAR: unbound variable\z/, msg)
  end

  def test_format_error_unbound_variable_style_standard
    msg = Rubish::Builtins.format_error('unbound variable', command: 'MY_VAR')
    assert_equal 'rubish: MY_VAR: unbound variable', msg
  end

  # Test circular nameref error with gnu_errfmt
  def test_circular_nameref_gnu_format
    execute('shopt -s gnu_errfmt')

    # Create circular nameref: a -> b -> a
    Rubish::Builtins.current_state.namerefs['circular_a'] = 'circular_b'
    Rubish::Builtins.current_state.namerefs['circular_b'] = 'circular_a'

    stderr = capture_stderr do
      Rubish::Builtins.resolve_nameref('circular_a')
    end

    # Should be in GNU format
    assert_match(/\A\w+:\d+: circular_[ab]: circular name reference\n\z/, stderr)
  ensure
    Rubish::Builtins.current_state.namerefs.delete('circular_a')
    Rubish::Builtins.current_state.namerefs.delete('circular_b')
  end

  # Test circular nameref error without gnu_errfmt
  def test_circular_nameref_standard_format
    Rubish::Builtins.current_state.namerefs['circular_a'] = 'circular_b'
    Rubish::Builtins.current_state.namerefs['circular_b'] = 'circular_a'

    stderr = capture_stderr do
      Rubish::Builtins.resolve_nameref('circular_a')
    end

    # Should be in standard format
    assert_match(/\Arubish: circular_[ab]: circular name reference\n\z/, stderr)
  ensure
    Rubish::Builtins.current_state.namerefs.delete('circular_a')
    Rubish::Builtins.current_state.namerefs.delete('circular_b')
  end

  # Test that format_error works when getters are not set
  def test_format_error_without_getters
    # Temporarily unset the getters
    original_source_getter = Rubish::Builtins.source_file_getter
    original_lineno_getter = Rubish::Builtins.lineno_getter

    Rubish::Builtins.source_file_getter = nil
    Rubish::Builtins.lineno_getter = nil

    execute('shopt -s gnu_errfmt')

    msg = Rubish::Builtins.format_error('test error')
    # Should fallback to 'rubish' and 0
    assert_equal 'rubish:0: test error', msg
  ensure
    Rubish::Builtins.source_file_getter = original_source_getter
    Rubish::Builtins.lineno_getter = original_lineno_getter
  end
end
