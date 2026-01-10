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

    assert_equal 'vi', Rubish::Builtins.readline_variables['editing-mode']
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

  def test_unescape_caret_control_chars
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('^a')
    assert_equal "\C-a", Rubish::Builtins.unescape_keyseq('^A')
    assert_equal "\x7F", Rubish::Builtins.unescape_keyseq('^?')
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
end
