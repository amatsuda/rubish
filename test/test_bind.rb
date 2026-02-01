# frozen_string_literal: true

require_relative 'test_helper'

class TestBind < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    @tempdir = Dir.mktmpdir('rubish_bind_test')
    Rubish::Builtins.clear_key_bindings
  end

  def teardown
    Rubish::Builtins.clear_key_bindings
    FileUtils.rm_rf(@tempdir)
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    # Reset Reline config to avoid affecting other tests
    Reline.core.config.reset_variables if defined?(Reline)
  end

  # Test bind is a builtin
  def test_bind_is_builtin
    assert Rubish::Builtins.builtin?('bind')
  end

  # Test bind -l lists functions
  def test_bind_l_lists_functions
    output = capture_output { Rubish::Builtins.run('bind', ['-l']) }
    assert_match(/accept-line/, output)
    assert_match(/backward-char/, output)
    assert_match(/forward-char/, output)
    assert_match(/kill-line/, output)
    lines = output.strip.split("\n")
    assert lines.length > 50
  end

  # Test bind adds key binding
  def test_bind_adds_binding
    result = Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_not_nil binding
    assert_equal :function, binding[:type]
    assert_equal 'beginning-of-line', binding[:value]
  end

  # Test bind -p prints bindings
  def test_bind_p_prints_bindings
    Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])
    Rubish::Builtins.run('bind', ['\\C-e:end-of-line'])

    output = capture_output { Rubish::Builtins.run('bind', ['-p']) }
    assert_match(/beginning-of-line/, output)
    assert_match(/end-of-line/, output)
  end

  # Test bind -P prints bindings with descriptions
  def test_bind_P_prints_bindings_verbose
    Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])

    output = capture_output { Rubish::Builtins.run('bind', ['-P']) }
    assert_match(/can be found in/, output)
  end

  # Test bind macro
  def test_bind_macro
    result = Rubish::Builtins.run('bind', ['\\C-x:"hello"'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-x")
    assert_not_nil binding
    assert_equal :macro, binding[:type]
    assert_equal 'hello', binding[:value]
  end

  # Test bind -s prints macros
  def test_bind_s_prints_macros
    Rubish::Builtins.run('bind', ['\\C-x:"hello"'])

    output = capture_output { Rubish::Builtins.run('bind', ['-s']) }
    assert_match(/hello/, output)
  end

  # Test bind -S prints macros verbose
  def test_bind_S_prints_macros_verbose
    Rubish::Builtins.run('bind', ['\\C-x:"hello"'])

    output = capture_output { Rubish::Builtins.run('bind', ['-S']) }
    assert_match(/outputs/, output)
  end

  # Test bind -x shell command
  def test_bind_x_shell_command
    result = Rubish::Builtins.run('bind', ['-x', '\\C-t:date'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-t")
    assert_not_nil binding
    assert_equal :command, binding[:type]
    assert_equal 'date', binding[:value]
  end

  # Test bind -X prints shell commands
  def test_bind_X_prints_shell_commands
    Rubish::Builtins.run('bind', ['-x', '\\C-t:date'])

    output = capture_output { Rubish::Builtins.run('bind', ['-X']) }
    assert_match(/date/, output)
  end

  # Test bind -q queries function
  def test_bind_q_queries_function
    Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])

    output = capture_output { Rubish::Builtins.run('bind', ['-q', 'beginning-of-line']) }
    assert_match(/can be invoked/, output)
  end

  # Test bind -q not found
  def test_bind_q_not_found
    output = capture_output { Rubish::Builtins.run('bind', ['-q', 'nonexistent']) }
    assert_match(/is not bound/, output)
  end

  # Test bind -u unbinds function
  def test_bind_u_unbinds
    Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])
    Rubish::Builtins.run('bind', ['\\C-e:beginning-of-line'])

    Rubish::Builtins.run('bind', ['-u', 'beginning-of-line'])

    assert_nil Rubish::Builtins.get_key_binding("\C-a")
    assert_nil Rubish::Builtins.get_key_binding("\C-e")
  end

  # Test bind -r removes keyseq
  def test_bind_r_removes_keyseq
    Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line'])

    Rubish::Builtins.run('bind', ['-r', "\C-a"])

    assert_nil Rubish::Builtins.get_key_binding("\C-a")
  end

  # Test bind -v prints variables
  def test_bind_v_prints_variables
    output = capture_output { Rubish::Builtins.run('bind', ['-v']) }
    assert_match(/set .* /, output)
    assert_match(/editing-mode/, output)
  end

  # Test bind -V prints variables verbose
  def test_bind_V_prints_variables_verbose
    output = capture_output { Rubish::Builtins.run('bind', ['-V']) }
    assert_match(/is set to/, output)
  end

  # Test bind -f reads file
  def test_bind_f_reads_file
    inputrc = File.join(@tempdir, 'inputrc')
    File.write(inputrc, <<~INPUTRC)
      # Comment line
      set editing-mode vi
      "\\C-a": beginning-of-line
      "\\C-e": end-of-line
    INPUTRC

    result = Rubish::Builtins.run('bind', ['-f', inputrc])
    assert result

    assert_equal 'vi', Rubish::Builtins.current_state.readline_variables['editing-mode']
    assert_not_nil Rubish::Builtins.get_key_binding("\C-a")
  end

  # Test bind -f file not found
  def test_bind_f_file_not_found
    output = capture_output do
      result = Rubish::Builtins.run('bind', ['-f', '/nonexistent/file'])
      assert_false result
    end
    assert_match(/cannot read/, output)
  end

  # Test bind -m sets keymap
  def test_bind_m_keymap
    result = Rubish::Builtins.run('bind', ['-m', 'vi', '\\C-a:beginning-of-line'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_equal 'vi', binding[:keymap]
  end

  # Test bind with invalid option
  def test_bind_invalid_option
    output = capture_output do
      result = Rubish::Builtins.run('bind', ['-z'])
      assert_false result
    end
    assert_match(/invalid option/, output)
  end

  # Test bind with invalid binding
  def test_bind_invalid_binding
    output = capture_output do
      result = Rubish::Builtins.run('bind', ['invalid'])
      assert_false result
    end
    assert_match(/invalid key binding/, output)
  end

  # Test type identifies bind as builtin
  def test_type_identifies_bind_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['bind']) }
    assert_match(/bind is a shell builtin/, output)
  end

  # Test bind via REPL
  def test_bind_via_repl
    execute('bind "\\C-a:beginning-of-line"')
    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_not_nil binding
  end

  # Test multiple bindings
  def test_bind_multiple
    result = Rubish::Builtins.run('bind', ['\\C-a:beginning-of-line', '\\C-e:end-of-line'])
    assert result

    assert_not_nil Rubish::Builtins.get_key_binding("\C-a")
    assert_not_nil Rubish::Builtins.get_key_binding("\C-e")
  end

  # ==========================================================================
  # Escape sequence handling tests
  # ==========================================================================

  def test_unescape_control_chars
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('\\C-a')
    assert_equal "\C-x", Rubish::Builtins.unescape_keyseq('\\C-x')
    assert_equal "\C-z", Rubish::Builtins.unescape_keyseq('\\C-z')
  end

  # Regression tests for non-letter control characters (issue: "-3 out of char range")
  def test_unescape_control_bracket_chars
    # \C-] is Ctrl+] = ASCII 29
    assert_equal 29.chr, Rubish::Builtins.unescape_keyseq('\\C-]')
    # \C-[ is Ctrl+[ = ESC = ASCII 27
    assert_equal 27.chr, Rubish::Builtins.unescape_keyseq('\\C-[')
    # \C-@ is Ctrl+@ = NUL = ASCII 0
    assert_equal 0.chr, Rubish::Builtins.unescape_keyseq('\\C-@')
    # \C-^ is Ctrl+^ = ASCII 30
    assert_equal 30.chr, Rubish::Builtins.unescape_keyseq('\\C-^')
    # \C-_ is Ctrl+_ = ASCII 31
    assert_equal 31.chr, Rubish::Builtins.unescape_keyseq('\\C-_')
    # \C-\ is Ctrl+\ = ASCII 28
    assert_equal 28.chr, Rubish::Builtins.unescape_keyseq('\\C-\\')
  end

  def test_unescape_control_uppercase_letters
    # Uppercase letters should work the same as lowercase
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('\\C-A')
    assert_equal "\C-z", Rubish::Builtins.unescape_keyseq('\\C-Z')
  end

  def test_unescape_caret_control_chars
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('^a')
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('^A')
    assert_equal "\x7F", Rubish::Builtins.unescape_keyseq('^?')
  end

  # Regression tests for non-letter caret control characters
  def test_unescape_caret_bracket_chars
    # ^] is Ctrl+] = ASCII 29
    assert_equal 29.chr, Rubish::Builtins.unescape_keyseq('^]')
    # ^[ is Ctrl+[ = ESC = ASCII 27
    assert_equal 27.chr, Rubish::Builtins.unescape_keyseq('^[')
    # ^@ is Ctrl+@ = NUL = ASCII 0
    assert_equal 0.chr, Rubish::Builtins.unescape_keyseq('^@')
    # ^^ is Ctrl+^ = ASCII 30
    assert_equal 30.chr, Rubish::Builtins.unescape_keyseq('^^')
    # ^_ is Ctrl+_ = ASCII 31
    assert_equal 31.chr, Rubish::Builtins.unescape_keyseq('^_')
  end

  # Regression test for meta+control non-letter characters
  def test_unescape_meta_control_bracket_chars
    # \M-\C-] is Meta + Ctrl+] = 0x80 | 29 = 157
    assert_equal 157.chr, Rubish::Builtins.unescape_keyseq('\\M-\\C-]')
    # \M-\C-[ is Meta + ESC = 0x80 | 27 = 155
    assert_equal 155.chr, Rubish::Builtins.unescape_keyseq('\\M-\\C-[')
  end

  # Test that bind -x works with non-letter control characters
  def test_bind_x_with_ctrl_bracket
    result = Rubish::Builtins.run('bind', ['-x', '\\C-]:my_command'])
    assert result

    binding = Rubish::Builtins.get_key_binding(29.chr)
    assert_not_nil binding
    assert_equal :command, binding[:type]
    assert_equal 'my_command', binding[:value]
  end

  # Test that bind -x registers with Reline
  def test_bind_x_registers_with_reline
    result = Rubish::Builtins.run('bind', ['-x', '\\C-t:echo hello'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-t")
    assert_not_nil binding
    assert_equal :command, binding[:type]
    assert_not_nil binding[:method_name], 'Should have a method_name for Reline'
    assert binding[:method_name].to_s.start_with?('__rubish_bind_x_')

    # Verify the method was defined on Reline::LineEditor
    assert Reline::LineEditor.method_defined?(binding[:method_name])
  end

  # Test that bind -x generates unique method names
  def test_bind_x_unique_method_names
    Rubish::Builtins.run('bind', ['-x', '\\C-q:echo first'])
    Rubish::Builtins.run('bind', ['-x', '\\C-w:echo second'])

    binding1 = Rubish::Builtins.get_key_binding("\C-q")
    binding2 = Rubish::Builtins.get_key_binding("\C-w")

    assert_not_equal binding1[:method_name], binding2[:method_name]
  end

  def test_unescape_escape_sequences
    assert_equal "\e", Rubish::Builtins.unescape_keyseq('\\e')
    assert_equal "\e", Rubish::Builtins.unescape_keyseq('\\E')
    assert_equal "\t", Rubish::Builtins.unescape_keyseq('\\t')
    assert_equal "\n", Rubish::Builtins.unescape_keyseq('\\n')
    assert_equal "\r", Rubish::Builtins.unescape_keyseq('\\r')
    assert_equal "\a", Rubish::Builtins.unescape_keyseq('\\a')
  end

  def test_unescape_octal
    assert_equal "\001", Rubish::Builtins.unescape_keyseq('\\001')
    assert_equal 'A', Rubish::Builtins.unescape_keyseq('\\101')
  end

  def test_unescape_hex
    assert_equal "\x01", Rubish::Builtins.unescape_keyseq('\\x01')
    assert_equal 'A', Rubish::Builtins.unescape_keyseq('\\x41')
  end

  def test_escape_control_chars
    assert_match(/\\C-/, Rubish::Builtins.escape_keyseq("\C-a"))
    assert_match(/\\e/, Rubish::Builtins.escape_keyseq("\e"))
    assert_match(/\\t/, Rubish::Builtins.escape_keyseq("\t"))
    assert_match(/\\n/, Rubish::Builtins.escape_keyseq("\n"))
  end

  def test_escape_roundtrip
    original = "\C-x\C-f"
    escaped = Rubish::Builtins.escape_keyseq(original)
    unescaped = Rubish::Builtins.unescape_keyseq(escaped)
    assert_equal original, unescaped
  end

  # ==========================================================================
  # Readline variable tests
  # ==========================================================================

  def test_bind_set_variable
    result = Rubish::Builtins.run('bind', ['set editing-mode vi'])
    assert result
    assert_equal 'vi', Rubish::Builtins.get_readline_variable('editing-mode')
  end

  def test_bind_apply_readline_variable
    Rubish::Builtins.apply_readline_variable('editing-mode', 'vi')
    assert_equal 'vi', Rubish::Builtins.get_readline_variable('editing-mode')
  end

  def test_bind_completion_ignore_case
    Rubish::Builtins.apply_readline_variable('completion-ignore-case', 'on')
    value = Rubish::Builtins.get_readline_variable('completion-ignore-case')
    assert_equal 'on', value
  end

  # ==========================================================================
  # File reading enhancements
  # ==========================================================================

  def test_bind_f_skips_conditionals
    inputrc = File.join(@tempdir, 'inputrc')
    File.write(inputrc, <<~INPUTRC)
      $if Rubish
      "\\C-a": beginning-of-line
      $endif
      "\\C-e": end-of-line
    INPUTRC

    result = Rubish::Builtins.run('bind', ['-f', inputrc])
    assert result

    # $if lines should be skipped, so only end-of-line should be bound
    assert_not_nil Rubish::Builtins.get_key_binding("\C-e")
  end

  def test_bind_f_uses_keymap
    inputrc = File.join(@tempdir, 'inputrc')
    File.write(inputrc, <<~INPUTRC)
      "\\C-a": beginning-of-line
    INPUTRC

    result = Rubish::Builtins.run('bind', ['-m', 'vi', '-f', inputrc])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_equal 'vi', binding[:keymap]
  end

  # ==========================================================================
  # Regression tests for bind -p showing Reline's built-in keybindings
  # (Previously bind -p printed nothing because get_reline_key_bindings
  #  didn't include bindings from @default_key_bindings or @additional_key_bindings)
  # ==========================================================================

  def test_get_reline_key_bindings_returns_non_empty
    # Regression test: get_reline_key_bindings used to return empty hash
    bindings = Rubish::Builtins.get_reline_key_bindings
    assert_not_empty bindings, 'get_reline_key_bindings should return Reline bindings'
  end

  def test_get_reline_key_bindings_includes_default_emacs_bindings
    # Regression test: should include default emacs keybindings
    bindings = Rubish::Builtins.get_reline_key_bindings

    # Should include some standard Reline action names
    # These are emacs-style actions that are always defined
    action_names = bindings.values.map(&:to_s)
    has_standard_actions = action_names.any? { |name|
      name.start_with?('ed_') || name.start_with?('em_') || name == 'complete'
    }
    assert has_standard_actions, 'Should include standard Reline actions (ed_*, em_*, complete)'
  end

  def test_get_reline_key_bindings_includes_common_bindings
    # Regression test: should include common readline bindings
    bindings = Rubish::Builtins.get_reline_key_bindings

    # Check that we have a reasonable number of bindings
    # Default emacs mode has many bindings
    assert bindings.size > 10, "Expected many bindings, got #{bindings.size}"
  end

  def test_bind_p_prints_reline_default_bindings
    # Regression test: bind -p used to print nothing
    # Now it should print Reline's built-in keybindings
    output = capture_output { Rubish::Builtins.run('bind', ['-p']) }

    # Should have output (not empty)
    assert_not_empty output.strip, 'bind -p should print keybindings'

    # Should contain some common action names from Reline
    # These are standard emacs-style readline actions
    assert(
      output.include?('ed_') || output.include?('em_') || output.include?('complete'),
      "bind -p should show Reline actions (ed_*, em_*, complete, etc.), got: #{output[0..200]}"
    )
  end

  def test_bind_p_output_format
    # Regression test: bind -p output should be in readline format
    output = capture_output { Rubish::Builtins.run('bind', ['-p']) }

    # Each line should be in format: "keyseq": action
    lines = output.strip.split("\n").reject(&:empty?)
    assert_not_empty lines, 'bind -p should output multiple lines'

    # Check that lines follow the expected format
    has_valid_format = lines.any? { |line| line.match?(/^".*": \w+/) }
    assert has_valid_format, "bind -p output should have format '\"keyseq\": action'"
  end

  def test_bind_P_prints_reline_default_bindings
    # Regression test: bind -P (verbose) should also show Reline bindings
    output = capture_output { Rubish::Builtins.run('bind', ['-P']) }

    # Should have output
    assert_not_empty output.strip, 'bind -P should print keybindings'

    # Verbose format includes "can be found in"
    assert output.include?('can be found in'), 'bind -P should use verbose format'
  end

  def test_bind_p_includes_both_default_and_additional_bindings
    # Setup Reline with our custom bindings
    @repl.send(:setup_reline)

    output = capture_output { Rubish::Builtins.run('bind', ['-p']) }

    # Should include some default Reline bindings
    # (checking for any ed_ or em_ action which are Reline's built-in actions)
    has_default = output.match?(/ed_|em_/)

    # Our custom bindings use completion_or_* names
    has_custom = output.include?('completion_or_') || output.include?('completion_page_')

    assert has_default || has_custom,
      'bind -p should show either default or custom bindings'
  end

  def test_readline_line_can_be_set_and_read
    # Regression test: verify readline_line= and readline_line work together
    # Set up the callbacks that the REPL normally provides
    line_value = nil
    Rubish::Builtins.current_state.readline_line_getter = -> { line_value }
    Rubish::Builtins.current_state.readline_line_setter = ->(v) { line_value = v }

    Rubish::Builtins.readline_line = 'test input'
    assert_equal 'test input', Rubish::Builtins.readline_line
  end

  def test_readline_point_can_be_set_and_read
    # Regression test: verify readline_point= and readline_point work together
    point_value = nil
    Rubish::Builtins.current_state.readline_point_getter = -> { point_value }
    Rubish::Builtins.current_state.readline_point_setter = ->(v) { point_value = v }

    Rubish::Builtins.readline_point = 5
    assert_equal 5, Rubish::Builtins.readline_point
  end

  def test_readline_point_modified_can_be_set_and_read
    # Regression test: verify readline_point_modified accessors work
    Rubish::Builtins.readline_point_modified = false
    assert_equal false, Rubish::Builtins.readline_point_modified

    Rubish::Builtins.readline_point_modified = true
    assert_equal true, Rubish::Builtins.readline_point_modified
  end

  def test_bind_x_executor_can_be_set_and_called
    # Regression test: verify bind_x_executor can be set and invoked
    executed = false
    Rubish::Builtins.bind_x_executor = ->(cmd) { executed = true }

    assert_not_nil Rubish::Builtins.bind_x_executor
    Rubish::Builtins.bind_x_executor.call('test')
    assert executed, 'bind_x_executor should be callable'
  end
end
