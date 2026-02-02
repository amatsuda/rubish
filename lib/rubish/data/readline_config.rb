# frozen_string_literal: true

module Rubish
  module Builtins
    # Readline function names for -l option
    READLINE_FUNCTIONS = %w[
      abort accept-line backward-char backward-delete-char backward-kill-line
      backward-kill-word backward-word beginning-of-history beginning-of-line
      call-last-kbd-macro capitalize-word character-search character-search-backward
      clear-screen complete delete-char delete-horizontal-space digit-argument
      do-lowercase-version downcase-word dump-functions dump-macros dump-variables
      emacs-editing-mode end-of-history end-of-line exchange-point-and-mark
      forward-backward-delete-char forward-char forward-search-history forward-word
      history-search-backward history-search-forward insert-comment insert-completions
      kill-line kill-region kill-whole-line kill-word menu-complete menu-complete-backward
      next-history non-incremental-forward-search-history non-incremental-reverse-search-history
      overwrite-mode possible-completions previous-history quoted-insert
      re-read-init-file redraw-current-line reverse-search-history revert-line
      self-insert set-mark shell-backward-kill-word shell-backward-word shell-expand-line
      shell-forward-word shell-kill-word start-kbd-macro tilde-expand transpose-chars
      transpose-words undo universal-argument unix-filename-rubout unix-line-discard
      unix-word-rubout upcase-word vi-append-eol vi-append-mode vi-arg-digit
      vi-bWord vi-back-to-indent vi-bword vi-change-case vi-change-char vi-change-to
      vi-char-search vi-column vi-complete vi-delete vi-delete-to vi-eWord vi-editing-mode
      vi-end-word vi-eof-maybe vi-eword vi-fWord vi-fetch-history vi-first-print
      vi-fword vi-goto-mark vi-insert-beg vi-insertion-mode vi-match vi-movement-mode
      vi-next-word vi-overstrike vi-overstrike-delete vi-prev-word vi-put vi-redo
      vi-replace vi-rubout vi-search vi-search-again vi-set-mark vi-subst vi-tilde-expand
      vi-undo vi-yank-arg vi-yank-to yank yank-last-arg yank-nth-arg yank-pop
    ].freeze

    # Readline variable names for -v/-V options
    READLINE_VARIABLES_LIST = %w[
      bell-style bind-tty-special-chars blink-matching-paren colored-completion-prefix
      colored-stats comment-begin completion-display-width completion-ignore-case
      completion-map-case completion-prefix-display-length completion-query-items
      convert-meta disable-completion echo-control-characters editing-mode
      emacs-mode-string enable-bracketed-paste enable-keypad expand-tilde
      history-preserve-point history-size horizontal-scroll-mode input-meta
      isearch-terminators keymap keyseq-timeout mark-directories mark-modified-lines
      mark-symlinked-directories match-hidden-files menu-complete-display-prefix
      output-meta page-completions print-completions-horizontally revert-all-at-newline
      show-all-if-ambiguous show-all-if-unmodified show-mode-in-prompt skip-completed-text
      vi-cmd-mode-string vi-ins-mode-string visible-stats
    ].freeze
  end
end
