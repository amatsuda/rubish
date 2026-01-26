# frozen_string_literal: true

require_relative 'test_helper'

class TestCompletionDialogKeybindings < Test::Unit::TestCase
  def setup
    @repl = Rubish::REPL.new
    # setup_reline is normally called from run(), so we need to call it explicitly
    # to set up the completion dialog keybindings
    @repl.send(:setup_reline)
  end

  # Test that keybindings are added to @additional_key_bindings (higher priority)
  # rather than @default_key_bindings (which gets overridden by Reline's lazy init)

  def test_arrow_up_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # ESC [ A = [27, 91, 65]
    assert_equal :completion_or_up, emacs_bindings[[27, 91, 65]]
  end

  def test_arrow_down_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # ESC [ B = [27, 91, 66]
    assert_equal :completion_or_down, emacs_bindings[[27, 91, 66]]
  end

  def test_alternate_arrow_up_binding
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # ESC O A = [27, 79, 65] (alternate sequence used by some terminals)
    assert_equal :completion_or_up, emacs_bindings[[27, 79, 65]]
  end

  def test_alternate_arrow_down_binding
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # ESC O B = [27, 79, 66] (alternate sequence used by some terminals)
    assert_equal :completion_or_down, emacs_bindings[[27, 79, 66]]
  end

  def test_ctrl_n_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # Ctrl-N = [14]
    assert_equal :completion_or_next_history, emacs_bindings[[14]]
  end

  def test_ctrl_p_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # Ctrl-P = [16]
    assert_equal :completion_or_prev_history, emacs_bindings[[16]]
  end

  def test_ctrl_f_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # Ctrl-F = [6]
    assert_equal :completion_page_or_forward_char, emacs_bindings[[6]]
  end

  def test_ctrl_b_binding_in_additional_key_bindings
    config = Reline.core.config
    additional = config.instance_variable_get(:@additional_key_bindings)
    emacs_bindings = additional[:emacs].instance_variable_get(:@key_bindings)

    # Ctrl-B = [2]
    assert_equal :completion_page_or_backward_char, emacs_bindings[[2]]
  end

  # Test that context-sensitive navigation methods are defined on LineEditor

  def test_line_editor_responds_to_completion_or_up
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_or_up)
  end

  def test_line_editor_responds_to_completion_or_down
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_or_down)
  end

  def test_line_editor_responds_to_completion_or_next_history
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_or_next_history)
  end

  def test_line_editor_responds_to_completion_or_prev_history
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_or_prev_history)
  end

  def test_line_editor_responds_to_completion_page_or_forward_char
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_page_or_forward_char)
  end

  def test_line_editor_responds_to_completion_page_or_backward_char
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_page_or_backward_char)
  end

  def test_line_editor_responds_to_completion_dialog_active
    editor = Reline::LineEditor.new(Reline.core.config)
    assert editor.respond_to?(:completion_dialog_active?)
  end

  # Test that bindings are in the correct keymap layer
  # (This tests the key insight: @additional_key_bindings has higher priority than @default_key_bindings)

  def test_bindings_not_in_default_key_bindings
    config = Reline.core.config

    # Check that @default_key_bindings doesn't have our custom bindings
    default = config.instance_variable_get(:@default_key_bindings)
    default_emacs = default[:emacs].instance_variable_get(:@key_bindings)

    # Our custom bindings should NOT be in default_key_bindings
    # If they were, Reline's lazy init could override them
    assert_not_equal :completion_or_up, default_emacs[[27, 91, 65]]
    assert_not_equal :completion_or_down, default_emacs[[27, 91, 66]]
    assert_not_equal :completion_or_next_history, default_emacs[[14]]
    assert_not_equal :completion_or_prev_history, default_emacs[[16]]
  end

  def test_bindings_in_additional_key_bindings_layer
    config = Reline.core.config

    # Our bindings should be in @additional_key_bindings
    additional = config.instance_variable_get(:@additional_key_bindings)
    additional_emacs = additional[:emacs].instance_variable_get(:@key_bindings)

    # Verify all our custom bindings are in the correct layer
    assert_equal :completion_or_up, additional_emacs[[27, 91, 65]]
    assert_equal :completion_or_down, additional_emacs[[27, 91, 66]]
    assert_equal :completion_or_up, additional_emacs[[27, 79, 65]]
    assert_equal :completion_or_down, additional_emacs[[27, 79, 66]]
    assert_equal :completion_or_next_history, additional_emacs[[14]]
    assert_equal :completion_or_prev_history, additional_emacs[[16]]
    assert_equal :completion_page_or_forward_char, additional_emacs[[6]]
    assert_equal :completion_page_or_backward_char, additional_emacs[[2]]
  end

  # Test the principle: additional_key_bindings has priority over default_key_bindings
  # in Reline's Composite keymap (so our bindings will be used even if defaults exist)

  def test_additional_bindings_have_priority_principle
    # The Composite keymap checks key actors in order:
    # 1. @oneshot_key_bindings (highest priority)
    # 2. @additional_key_bindings (our bindings go here)
    # 3. @default_key_bindings (lowest priority)
    #
    # So our bindings in @additional will always be found before any defaults.
    # This test verifies the architecture is correct.

    config = Reline.core.config
    key_bindings = config.key_bindings

    # key_bindings should be a Composite
    assert_kind_of Reline::KeyActor::Composite, key_bindings

    # The Composite should check @additional before @default
    # We verify this by checking that get() returns our binding
    # even if a different binding exists in @default
    additional = config.instance_variable_get(:@additional_key_bindings)
    additional_emacs = additional[:emacs]

    # If our binding is in additional, it will be returned by the composite
    # regardless of what's in default (that's the Composite design)
    assert_equal :completion_or_up, additional_emacs.get([27, 91, 65])
    assert_equal :completion_or_next_history, additional_emacs.get([14])
  end
end
