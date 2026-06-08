# frozen_string_literal: true

require 'reline'

module Rubish
  module Frontend
    # Default frontend: runs in a real terminal via Reline. The original
    # rubish behavior, extracted into a Frontend so other hosts (e.g.
    # an in-process Echoes embedding) can swap the I/O surface out.
    class Tty < Base
      # Reline.readline gained the `rprompt:` keyword argument in a
      # specific version; older Relines only accept the positional
      # `(prompt, add_to_history = false)` form. Detect once.
      RELINE_SUPPORTS_RPROMPT =
        Reline::Core.instance_method(:readline).parameters.any? { |_, n| n == :rprompt }

      def read_line(prompt:, rprompt: nil)
        prompt = render_prompt_prefix(prompt)
        with_interrupt_trap do
          if RELINE_SUPPORTS_RPROMPT
            Reline.readline(prompt: prompt, rprompt: rprompt || '')
          else
            Reline.readline(prompt, false)
          end
        end
      end

      def read_continuation_line(prompt)
        prompt = render_prompt_prefix(prompt)
        with_interrupt_trap { Reline.readline(prompt, false) }
      end

      # Reline renders embedded `\n` in the prompt as literal two-char
      # `\n` sequences. Multi-line prompts (e.g. starship's
      # `\nrubish on master\n❯`) need the leading lines printed straight
      # to stdout before readline so only the final line is the
      # readline-managed prompt. Matches bash/zsh's behaviour.
      def render_prompt_prefix(prompt)
        Tty.last_prompt_prefix = nil
        return prompt unless prompt.include?("\n")
        prefix, _, last = prompt.rpartition("\n")
        print "#{prefix}\n"
        $stdout.flush
        # Stash so the Ctrl-L handler can re-emit it after clear-screen.
        Tty.last_prompt_prefix = "#{prefix}\n"
        last
      end

      class << self
        # Set on every prompt cycle by render_prompt_prefix above; read
        # by the PromptPrefixRedraw Reline patch when Ctrl-L fires.
        attr_accessor :last_prompt_prefix
      end

      def read_simple_line(prompt = '')
        with_interrupt_trap { Reline.readline(prompt, false) }
      end

      def insert_text(text)
        return if Reline.pre_input_hook
        Reline.pre_input_hook = -> {
          Reline.insert_text(text)
          Reline.pre_input_hook = nil
        }
      end

      def setup_completion(&block)
        Reline.completion_proc = block
      end

      private

      # rubish installs `trap('INT') { }` at startup so the shell stays
      # alive when SIGINT goes to a foreground child. Inside the
      # readline call we want different SIGINT behavior — echo `^C`
      # where the cursor is, then propagate Interrupt so the REPL paints
      # a fresh prompt — so swap in a `raise Interrupt` trap for the
      # duration of the readline call and restore the shell-wide empty
      # trap on the way out.
      #
      # That alone gets us Interrupt propagation, but not the `^C` in
      # the right spot: Reline's handle_interrupted moves the cursor
      # down BEFORE calling back through our trap, so any output from
      # the trap lands on the new line, not next to the user's input.
      # The CtrlCEcho prepend below patches handle_interrupted to write
      # `^C` first, while the cursor is still at the typing position.
      def with_interrupt_trap
        outer_old = trap('INT') { raise Interrupt }
        yield
      ensure
        trap('INT', outer_old)
      end
    end

    # Reline doesn't write a `^C` of its own — handle_interrupted just
    # scrolls down to a fresh line and calls back through @old_trap.
    # Patch the method to echo the marker between `render` and
    # `scroll_down`: render leaves the cursor at the end of the typed
    # input, which is where we want `^C` to appear. Writing it BEFORE
    # render would get overwritten when render redraws the buffer;
    # writing it AFTER scroll_down puts it on the wrong line. The body
    # is a copy of Reline 0.6.3's handle_interrupted with one inserted
    # line; if Reline changes the surrounding logic we'll need to
    # follow it, but the surface area is small.
    #
    # Result matches bash / GNU readline:
    #
    #     $ ls^C
    #     $
    #
    # (Reline runs the tty in raw mode, so the kernel's echoctl doesn't
    # do this for us.)
    module CtrlCEcho
      private def handle_interrupted
        return unless @interrupted

        @interrupted = false
        clear_dialogs
        render
        Reline::IOGate.write '^C'
        cursor_to_bottom_offset = @rendered_screen.lines.size - @rendered_screen.cursor_y
        Reline::IOGate.scroll_down cursor_to_bottom_offset
        Reline::IOGate.move_cursor_column 0
        clear_rendered_screen_cache
        case @old_trap
        when 'DEFAULT', 'SYSTEM_DEFAULT'
          raise Interrupt
        when 'IGNORE'
          # Do nothing
        when 'EXIT'
          exit
        else
          @old_trap.call if @old_trap.respond_to?(:call)
        end
      end
    end
    Reline::LineEditor.prepend(CtrlCEcho)

    # Ctrl-L is handled entirely inside Reline (ed_clear_screen): it
    # clears the screen and re-renders only its own prompt — which is
    # the FINAL line of a multi-line prompt for us (render_prompt_prefix
    # above already printed the rest to stdout). After Ctrl-L the prefix
    # is gone, leaving just `❯ ` floating at the top of the cleared screen.
    # Re-emit the prefix right after Reline's clear, then bump base_y so
    # Reline draws its prompt below it.
    module PromptPrefixRedraw
      private def ed_clear_screen(key)
        super
        prefix = Tty.last_prompt_prefix
        return unless prefix && !prefix.empty?

        Reline::IOGate.write prefix
        # Number of rows the prefix consumed = newline count. base_y is
        # the row Reline considers row 0 for its own rendering, so
        # bumping it lets the prompt redraw below the prefix instead of
        # on top of it.
        @rendered_screen.base_y = prefix.count("\n")
      end
    end
    Reline::LineEditor.prepend(PromptPrefixRedraw)
  end
end
