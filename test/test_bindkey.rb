# frozen_string_literal: true

require_relative 'test_helper'

class TestBindkey < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    @original_env = ENV.to_h.dup
    Rubish::Builtins.clear_key_bindings
  end

  def teardown
    Rubish::Builtins.clear_key_bindings
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  # Test bindkey is a builtin
  def test_bindkey_is_builtin
    assert Rubish::Builtins.builtin?('bindkey')
  end

  # Test bindkey -l lists keymaps
  def test_bindkey_l_lists_keymaps
    output = capture_output { Rubish::Builtins.run('bindkey', ['-l']) }
    assert_match(/emacs/, output)
    assert_match(/viins/, output)
    assert_match(/vicmd/, output)
    assert_match(/visual/, output)
    assert_match(/isearch/, output)
  end

  # Test bindkey adds key binding
  def test_bindkey_adds_binding
    result = Rubish::Builtins.run('bindkey', ['^A', 'beginning-of-line'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_not_nil binding
    assert_equal :function, binding[:type]
    assert_equal 'beginning-of-line', binding[:value]
  end

  # Test bindkey shows binding for key
  def test_bindkey_shows_binding
    Rubish::Builtins.run('bindkey', ['^A', 'beginning-of-line'])

    output = capture_output { Rubish::Builtins.run('bindkey', ['^A']) }
    assert_match(/beginning-of-line/, output)
  end

  # Test bindkey shows undefined for unbound key
  def test_bindkey_shows_undefined
    output = capture_output { Rubish::Builtins.run('bindkey', ['^Z']) }
    assert_match(/undefined-key/, output)
  end

  # Test bindkey lists all bindings with no args
  def test_bindkey_lists_bindings
    Rubish::Builtins.run('bindkey', ['^A', 'beginning-of-line'])
    Rubish::Builtins.run('bindkey', ['^E', 'end-of-line'])

    output = capture_output { Rubish::Builtins.run('bindkey', []) }
    assert_match(/beginning-of-line/, output)
    assert_match(/end-of-line/, output)
  end

  # Test bindkey -L outputs rebindable format
  def test_bindkey_L_format
    Rubish::Builtins.run('bindkey', ['^A', 'beginning-of-line'])

    output = capture_output { Rubish::Builtins.run('bindkey', ['-L']) }
    assert_match(/beginning-of-line/, output)
  end

  # Test bindkey -r removes binding
  def test_bindkey_r_removes_binding
    Rubish::Builtins.run('bindkey', ['^A', 'beginning-of-line'])
    assert_not_nil Rubish::Builtins.get_key_binding("\C-a")

    Rubish::Builtins.run('bindkey', ['-r', '^A'])
    assert_nil Rubish::Builtins.get_key_binding("\C-a")
  end

  # Test bindkey -s creates macro binding
  def test_bindkey_s_macro
    result = Rubish::Builtins.run('bindkey', ['-s', '^X', 'hello'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-x")
    assert_not_nil binding
    assert_equal :macro, binding[:type]
  end

  # Test bindkey -e selects emacs keymap
  def test_bindkey_e_emacs
    Rubish::Builtins.run('bindkey', ['-e'])
    assert_equal 'emacs', Rubish::Builtins.get_readline_variable('editing-mode')
  end

  # Test bindkey -v selects viins keymap
  def test_bindkey_v_viins
    Rubish::Builtins.run('bindkey', ['-v'])
    assert_equal 'vi', Rubish::Builtins.get_readline_variable('editing-mode')
  end

  # Test bindkey -a selects vicmd keymap
  def test_bindkey_a_vicmd
    Rubish::Builtins.run('bindkey', ['-a'])
    assert_equal 'vi', Rubish::Builtins.get_readline_variable('editing-mode')
  end

  # Test bindkey -M specifies keymap for binding
  def test_bindkey_M_keymap
    result = Rubish::Builtins.run('bindkey', ['-M', 'viins', '^A', 'beginning-of-line'])
    assert result

    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_equal 'viins', binding[:keymap]
  end

  # Test bindkey bad option
  def test_bindkey_bad_option
    output = capture_output do
      result = Rubish::Builtins.run('bindkey', ['-z'])
      assert_false result
    end
    assert_match(/bad option/, output)
  end

  # Test type identifies bindkey as builtin
  def test_type_identifies_bindkey_as_builtin
    output = capture_output { Rubish::Builtins.run('type', ['bindkey']) }
    assert_match(/bindkey is a shell builtin/, output)
  end

  # Test bindkey via REPL
  def test_bindkey_via_repl
    execute('bindkey "^A" beginning-of-line')
    binding = Rubish::Builtins.get_key_binding("\C-a")
    assert_not_nil binding
  end

  # ==========================================================================
  # Key sequence parsing tests
  # ==========================================================================

  def test_parse_bindkey_keyseq_caret
    # ^X notation
    assert_equal "\C-a", Rubish::Builtins.parse_bindkey_keyseq('^A')
    assert_equal "\C-a", Rubish::Builtins.parse_bindkey_keyseq('^a')
    assert_equal "\C-x", Rubish::Builtins.parse_bindkey_keyseq('^X')
    assert_equal "\x7F", Rubish::Builtins.parse_bindkey_keyseq('^?')  # DEL
    assert_equal "\e", Rubish::Builtins.parse_bindkey_keyseq('^[')    # ESC
  end

  def test_parse_bindkey_keyseq_backslash_e
    # \e notation for ESC
    assert_equal "\e", Rubish::Builtins.parse_bindkey_keyseq('\e')
    assert_equal "\e", Rubish::Builtins.parse_bindkey_keyseq('\E')
  end

  def test_parse_bindkey_keyseq_backslash_C
    # \C-x notation
    assert_equal "\C-a", Rubish::Builtins.parse_bindkey_keyseq('\C-a')
    assert_equal "\C-x", Rubish::Builtins.parse_bindkey_keyseq('\C-x')
  end

  def test_parse_bindkey_keyseq_backslash_M
    # \M-x notation (Meta = ESC + char)
    assert_equal "\ea", Rubish::Builtins.parse_bindkey_keyseq('\M-a')
    assert_equal "\ex", Rubish::Builtins.parse_bindkey_keyseq('\M-x')
  end

  def test_parse_bindkey_keyseq_escape_sequences
    # Standard escape sequences
    assert_equal "\n", Rubish::Builtins.parse_bindkey_keyseq('\n')
    assert_equal "\r", Rubish::Builtins.parse_bindkey_keyseq('\r')
    assert_equal "\t", Rubish::Builtins.parse_bindkey_keyseq('\t')
    assert_equal '\\', Rubish::Builtins.parse_bindkey_keyseq('\\\\')
  end

  def test_parse_bindkey_keyseq_arrow_keys
    # Arrow key sequences
    assert_equal "\e[A", Rubish::Builtins.parse_bindkey_keyseq('\e[A')  # Up
    assert_equal "\e[B", Rubish::Builtins.parse_bindkey_keyseq('\e[B')  # Down
    assert_equal "\e[C", Rubish::Builtins.parse_bindkey_keyseq('\e[C')  # Right
    assert_equal "\e[D", Rubish::Builtins.parse_bindkey_keyseq('\e[D')  # Left
  end

  def test_parse_bindkey_keyseq_with_quotes
    # Handles quoted strings
    assert_equal "\C-a", Rubish::Builtins.parse_bindkey_keyseq('"^A"')
    assert_equal "\C-a", Rubish::Builtins.parse_bindkey_keyseq("'^A'")
  end

  def test_parse_bindkey_keyseq_empty_and_nil
    assert_equal '', Rubish::Builtins.parse_bindkey_keyseq('')
    assert_nil Rubish::Builtins.parse_bindkey_keyseq(nil)
  end

  # ==========================================================================
  # Key sequence formatting tests
  # ==========================================================================

  def test_format_bindkey_keyseq_control_chars
    assert_equal '^A', Rubish::Builtins.format_bindkey_keyseq("\C-a")
    assert_equal '^X', Rubish::Builtins.format_bindkey_keyseq("\C-x")
    assert_equal '^[', Rubish::Builtins.format_bindkey_keyseq("\e")
    assert_equal '^?', Rubish::Builtins.format_bindkey_keyseq("\x7F")
  end

  def test_format_bindkey_keyseq_printable
    assert_equal 'a', Rubish::Builtins.format_bindkey_keyseq('a')
    assert_equal 'hello', Rubish::Builtins.format_bindkey_keyseq('hello')
  end

  def test_format_bindkey_keyseq_arrow_keys
    assert_equal '^[[A', Rubish::Builtins.format_bindkey_keyseq("\e[A")
    assert_equal '^[[B', Rubish::Builtins.format_bindkey_keyseq("\e[B")
  end

  def test_format_bindkey_keyseq_empty_and_nil
    assert_equal '', Rubish::Builtins.format_bindkey_keyseq('')
    assert_equal '', Rubish::Builtins.format_bindkey_keyseq(nil)
  end

  # ==========================================================================
  # Roundtrip tests
  # ==========================================================================

  def test_parse_format_roundtrip_control
    original = "\C-a"
    formatted = Rubish::Builtins.format_bindkey_keyseq(original)
    parsed = Rubish::Builtins.parse_bindkey_keyseq(formatted)
    assert_equal original, parsed
  end

  def test_parse_format_roundtrip_escape
    original = "\e"
    formatted = Rubish::Builtins.format_bindkey_keyseq(original)
    parsed = Rubish::Builtins.parse_bindkey_keyseq(formatted)
    assert_equal original, parsed
  end
end
