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

    # Traps state
    attr_accessor :traps, :original_traps, :current_trapsig

    # Completion state
    attr_accessor :completions, :completion_options, :current_completion_options

    # Key bindings state
    attr_accessor :key_bindings, :readline_variables

    # History state
    attr_accessor :history_timestamps

    # Execution callbacks
    attr_accessor :executor, :command_executor, :heredoc_content_setter

    # Script/position callbacks
    attr_accessor :script_name_getter, :script_name_setter
    attr_accessor :positional_params_getter, :positional_params_setter
    attr_accessor :lineno_getter

    # Function callbacks
    attr_accessor :function_checker, :function_remover, :function_lister, :function_getter, :function_caller
    attr_accessor :autoload_functions

    # History callbacks
    attr_accessor :history_file_getter, :history_loader, :history_saver, :history_appender
    attr_accessor :last_history_line

    # Source file callbacks
    attr_accessor :source_file_getter, :source_file_setter

    # Readline callbacks
    attr_accessor :readline_line_getter, :readline_line_setter
    attr_accessor :readline_point_getter, :readline_point_setter
    attr_accessor :readline_mark_getter, :readline_mark_setter
    attr_accessor :readline_point_modified

    # Misc callbacks and state
    attr_accessor :bash_argv0_unsetter
    attr_accessor :bind_x_executor, :bind_x_counter
    attr_accessor :exit_blocked_by_jobs
    attr_accessor :sourcing_file
    attr_accessor :source_executor

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

      # Traps state
      @traps = {}
      @original_traps = {}
      @current_trapsig = ''

      # Completion state
      @completions = {}
      @completion_options = {}
      @current_completion_options = Set.new

      # Key bindings state
      @key_bindings = {}
      @readline_variables = {}

      # History state
      @history_timestamps = {}

      # Execution callbacks (nil by default, set by REPL)
      @executor = nil
      @command_executor = nil
      @heredoc_content_setter = nil

      # Script/position callbacks
      @script_name_getter = nil
      @script_name_setter = nil
      @positional_params_getter = nil
      @positional_params_setter = nil
      @lineno_getter = nil

      # Function callbacks
      @function_checker = nil
      @function_remover = nil
      @function_lister = nil
      @function_getter = nil
      @function_caller = nil
      @autoload_functions = {}

      # History callbacks
      @history_file_getter = nil
      @history_loader = nil
      @history_saver = nil
      @history_appender = nil
      @last_history_line = 0

      # Source file callbacks
      @source_file_getter = nil
      @source_file_setter = nil

      # Readline callbacks
      @readline_line_getter = nil
      @readline_line_setter = nil
      @readline_point_getter = nil
      @readline_point_setter = nil
      @readline_mark_getter = nil
      @readline_mark_setter = nil
      @readline_point_modified = nil

      # Misc callbacks and state
      @bash_argv0_unsetter = nil
      @bind_x_executor = nil
      @bind_x_counter = 0
      @exit_blocked_by_jobs = false
      @sourcing_file = nil
      @source_executor = nil
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

    def clear_traps
      @traps.clear
      @original_traps.clear
      @current_trapsig = ''
    end

    def clear_completions
      @completions.clear
      @completion_options.clear
      @current_completion_options.clear
    end

    def clear_key_bindings
      @key_bindings.clear
      @readline_variables.clear
    end

    def clear_history_timestamps
      @history_timestamps.clear
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
