# frozen_string_literal: true

module Rubish
  # ShellState holds per-session shell state as instance variables.
  # This enables proper isolation between shell sessions and simplifies testing.
  class ShellState
    # Variables state
    attr_accessor :shell_vars, :arrays, :assoc_arrays, :namerefs, :var_attributes, :readonly_vars, :local_scope_stack

    # Options state
    attr_accessor :shell_options, :zsh_options, :set_options

    # Aliases and hash table state
    attr_accessor :aliases, :command_hash

    # Directory stack state
    attr_accessor :dir_stack

    def initialize
      # Variables state
      @shell_vars = {}
      @arrays = {}
      @assoc_arrays = {}
      @namerefs = {}
      @var_attributes = {}
      @readonly_vars = {}
      @local_scope_stack = []

      # Options state
      @shell_options = {}
      @zsh_options = {}
      @set_options = default_set_options

      # Aliases and hash table state
      @aliases = {}
      @command_hash = {}

      # Directory stack state
      @dir_stack = []
    end

    def clear_variables
      @shell_vars.clear
      @arrays.clear
      @assoc_arrays.clear
      @namerefs.clear
      @var_attributes.clear
      @readonly_vars.clear
      @local_scope_stack.clear
    end

    def clear_options
      @shell_options.clear
      @zsh_options.clear
      @set_options = default_set_options
    end

    def clear_aliases
      @aliases.clear
    end

    def clear_hash
      @command_hash.clear
    end

    def clear_dir_stack
      @dir_stack.clear
    end

    private

    def default_set_options
      {
        'B' => true,   # braceexpand: enable brace expansion (enabled by default)
        'H' => true,   # histexpand: enable ! style history expansion (enabled by default)
        'e' => false,  # errexit: exit on error
        'E' => false,  # errtrace: ERR trap inherited by functions/subshells
        'T' => false,  # functrace: DEBUG/RETURN traps inherited by functions/subshells
        'x' => false,  # xtrace: print commands
        'u' => false,  # nounset: error on unset variables
        'n' => false,  # noexec: don't execute (syntax check)
        'v' => false,  # verbose: print input lines
        'f' => false,  # noglob: disable globbing
        'C' => false,  # noclobber: don't overwrite files with >
        'a' => false,  # allexport: export all variables
        'b' => false,  # notify: report job status immediately
        'h' => false,  # hashall: hash commands
        'm' => false,  # monitor: job control
        'pipefail' => false,  # pipefail: pipeline fails if any command fails
        'globstar' => false,  # globstar: ** matches directories recursively
        'nullglob' => false,  # nullglob: patterns matching nothing expand to nothing
        'failglob' => false,  # failglob: patterns matching nothing cause an error
        'dotglob' => false,   # dotglob: globs match files starting with .
        'nocaseglob' => false, # nocaseglob: case-insensitive globbing
        'ignoreeof' => false,  # ignoreeof: don't exit on EOF (Ctrl+D)
        'extglob' => false,    # extglob: extended pattern matching operators
        'P' => false,          # physical: don't follow symlinks for cd/pwd
        'emacs' => true,       # emacs: use emacs-style line editing (default)
        'vi' => false,         # vi: use vi-style line editing
        'nocasematch' => false, # nocasematch: case-insensitive pattern matching in case/[[
        't' => false,          # onecmd: exit after reading and executing one command
        'k' => false,          # keyword: all assignment args placed in environment
        'p' => false,          # privileged: don't read startup files, ignore some env vars
        'history' => true,     # history: enable command history (enabled by default)
        'nolog' => false,      # nolog: obsolete, has no effect
        'r' => false,          # restricted: restricted shell mode (cannot be disabled once set)
        'i' => false,          # interactive: shell is interactive (read-only, set at startup)
      }
    end
  end
end
