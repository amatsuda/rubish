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
end
