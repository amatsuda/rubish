# frozen_string_literal: true

module Rubish
  module Builtins
    COMMANDS = %w(cd exit logout jobs fg bg export pwd history alias unalias source . shift set return read echo test [ break continue pushd popd dirs trap getopts local unset readonly declare typeset let printf type which true false : eval command builtin wait kill umask exec times hash disown ulimit suspend shopt enable caller complete compgen compopt bind help fc mapfile readarray basename dirname realpath _get_comp_words_by_ref _init_completion _filedir _have _split_longopt __ltrim_colon_completions _variables _tilde _quote_readline_by_ref _parse_help _upvars _usergroup setopt unsetopt).freeze

    @aliases = {}
    @dir_stack = []
    @traps = {}
    @original_traps = {}
    @current_trapsig = ''  # Signal name when trap handler is executing (for RUBISH_TRAPSIG/BASH_TRAPSIG)
    @local_scope_stack = []  # Stack of hashes for local variable scopes
    @readonly_vars = {}  # Hash of readonly variable names to their values
    @var_attributes = {}  # Hash of variable names to Set of attributes (:integer, :lowercase, :uppercase, :export)
    @command_hash = {}  # Hash of command names to their cached paths
    @shell_options = {}  # Hash of shell option names to boolean values
    @zsh_options = {}  # Hash of zsh-specific option names to boolean values
    @disabled_builtins = Set.new  # Set of disabled builtin names
    @dynamic_commands = []  # Array of dynamically loaded builtin names
    @call_stack = []  # Stack of [line_number, function_name, filename] for caller builtin
    @completions = {}  # Hash of command names to completion specs
    @completion_options = {}  # Hash of command names to Set of completion options
    @current_completion_options = Set.new  # Options for currently executing completion
    @key_bindings = {}  # Hash of keyseq to function/macro/command
    @readline_variables = {}  # Hash of readline variable names to values
    @arrays = {}  # Hash of array variable names to their values (Array)
    @assoc_arrays = {}  # Hash of associative array names to their values (Hash)
    @namerefs = {}  # Hash of nameref variable names to their target variable names
    @coprocs = {}  # Hash of coproc names to {pid:, read_fd:, write_fd:, reader:, writer:}
    @executor = nil
    @script_name_getter = nil
    @script_name_setter = nil
    @positional_params_getter = nil
    @positional_params_setter = nil
    @function_checker = nil
    @function_remover = nil
    @function_lister = nil  # Returns hash of all functions {name => {source:, file:}}
    @function_getter = nil  # Returns function info for a specific name
    @function_caller = nil  # Calls a function with args, returns success boolean
    @heredoc_content_setter = nil
    @command_executor = nil  # Executor that bypasses functions/aliases
    @history_file_getter = nil  # Gets HISTFILE path
    @history_loader = nil  # Loads history from file
    @history_saver = nil  # Saves history to file
    @history_appender = nil  # Appends new entries to file
    @last_history_line = 0  # Track last line read for -n option
    @history_timestamps = {}  # Timestamps for history entries (index => Time)
    @source_file_getter = nil  # Gets current source file for RUBISH_SOURCE
    @source_file_setter = nil  # Sets current source file for RUBISH_SOURCE
    @lineno_getter = nil  # Gets current line number for LINENO
    @exit_blocked_by_jobs = false  # Track if exit was blocked due to running jobs (for checkjobs)
    @builtin_completion_functions = {}  # Hash of function names to lambdas for builtin completions

    class << self
      attr_reader :aliases, :dir_stack, :traps, :local_scope_stack, :readonly_vars, :var_attributes, :command_hash, :shell_options, :zsh_options, :disabled_builtins, :call_stack, :completions, :completion_options, :key_bindings, :readline_variables, :arrays, :assoc_arrays, :namerefs, :coprocs, :builtin_completion_functions
      attr_accessor :current_trapsig
      attr_accessor :executor, :script_name_getter, :script_name_setter, :positional_params_getter, :positional_params_setter, :function_checker, :function_remover, :function_lister, :function_getter, :function_caller, :heredoc_content_setter, :command_executor, :current_completion_options
      attr_accessor :history_file_getter, :history_loader, :history_saver, :history_appender, :last_history_line, :history_timestamps
      attr_accessor :source_file_getter, :source_file_setter
      attr_accessor :lineno_getter
      attr_accessor :bash_argv0_unsetter
      attr_accessor :readline_line_getter, :readline_line_setter, :readline_point_getter, :readline_point_setter, :readline_mark_getter, :readline_mark_setter
      attr_accessor :exit_blocked_by_jobs
      attr_accessor :sourcing_file  # True when sourcing a file (disables history expansion)
    end

    # Format error message based on gnu_errfmt setting
    # Standard format: "rubish: message"
    # GNU format: "rubish:source:lineno: message"
    def self.format_error(message, command: nil)
      prefix = if command
                 "rubish: #{command}: "
               else
                 'rubish: '
               end

      if shopt_enabled?('gnu_errfmt')
        source = @source_file_getter&.call || 'rubish'
        lineno = @lineno_getter&.call || 0
        "#{source}:#{lineno}: #{prefix.sub(/\Arubish: /, '')}#{message}"
      else
        "#{prefix}#{message}"
      end
    end

    # Array variable methods
    def self.array?(name)
      @arrays.key?(name)
    end

    def self.get_array(name)
      @arrays[name] || []
    end

    def self.set_array(name, values)
      @arrays[name] = values.is_a?(Array) ? values : [values]
    end

    def self.get_array_element(name, index)
      arr = @arrays[name]
      return '' unless arr
      arr[index.to_i] || ''
    end

    def self.set_array_element(name, index, value)
      @arrays[name] ||= []
      @arrays[name][index.to_i] = value
    end

    def self.indexed_array?(name)
      @arrays.key?(name)
    end

    def self.array_length(name)
      (@arrays[name] || []).length
    end

    def self.array_append(name, values)
      @arrays[name] ||= []
      @arrays[name].concat(values.is_a?(Array) ? values : [values])
    end

    def self.unset_array(name)
      @arrays.delete(name)
    end

    def self.unset_array_element(name, index)
      return unless @arrays[name]
      @arrays[name][index.to_i] = nil
    end

    # Associative array methods
    def self.assoc_array?(name)
      @assoc_arrays.key?(name)
    end

    def self.declare_assoc_array(name)
      @assoc_arrays[name] ||= {}
    end

    def self.get_assoc_array(name)
      @assoc_arrays[name] || {}
    end

    def self.set_assoc_array(name, hash)
      @assoc_arrays[name] = hash.is_a?(Hash) ? hash : {}
    end

    def self.get_assoc_element(name, key)
      hash = @assoc_arrays[name]
      return '' unless hash
      hash[key] || ''
    end

    def self.set_assoc_element(name, key, value)
      @assoc_arrays[name] ||= {}
      @assoc_arrays[name][key] = value
    end

    def self.assoc_keys(name)
      (@assoc_arrays[name] || {}).keys
    end

    def self.assoc_values(name)
      (@assoc_arrays[name] || {}).values
    end

    def self.assoc_length(name)
      (@assoc_arrays[name] || {}).length
    end

    def self.unset_assoc_array(name)
      @assoc_arrays.delete(name)
    end

    def self.unset_assoc_element(name, key)
      return unless @assoc_arrays[name]
      @assoc_arrays[name].delete(key)
    end

    # Nameref (reference variable) methods
    def self.nameref?(name)
      (@var_attributes[name] || Set.new).include?(:nameref)
    end

    def self.resolve_nameref(name, visited = Set.new)
      # Resolve nameref chain, detecting circular references
      return name unless @namerefs.key?(name)

      if visited.include?(name)
        $stderr.puts format_error('circular name reference', command: name)
        return nil
      end

      visited << name
      target = @namerefs[name]
      resolve_nameref(target, visited)
    end

    def self.get_nameref_target(name)
      @namerefs[name]
    end

    def self.set_nameref(name, target)
      @namerefs[name] = target
      @var_attributes[name] ||= Set.new
      @var_attributes[name] << :nameref
    end

    def self.unset_nameref(name)
      @namerefs.delete(name)
      @var_attributes[name]&.delete(:nameref)
    end

    def self.get_var_through_nameref(name)
      # If it's a nameref, get the value of the target variable
      if nameref?(name)
        target = resolve_nameref(name)
        return '' if target.nil?
        # Check if target is an array or assoc array
        if array?(target)
          return get_array(target).join(' ')
        elsif assoc_array?(target)
          return get_assoc_array(target).values.join(' ')
        else
          return ENV[target] || ''
        end
      end
      ENV[name] || ''
    end

    def self.set_var_through_nameref(name, value)
      # If it's a nameref, set the value of the target variable
      if nameref?(name)
        target = resolve_nameref(name)
        return false if target.nil?
        # Check if target is an array
        if array?(target)
          set_array_element(target, 0, value)
        elsif assoc_array?(target)
          $stderr.puts format_error('cannot assign to associative array through nameref', command: name)
          return false
        else
          ENV[target] = value
        end
        return true
      end
      ENV[name] = value
      true
    end

    def self.clear_namerefs
      @namerefs.each_key do |name|
        @var_attributes[name]&.delete(:nameref)
      end
      @namerefs.clear
    end

    # IFS (Internal Field Separator) methods
    DEFAULT_IFS = " \t\n"

    # COMP_WORDBREAKS - characters that separate words for completion
    DEFAULT_COMP_WORDBREAKS = " \t\n\"'><=;|&(:"

    def self.comp_wordbreaks
      ENV['COMP_WORDBREAKS'] || DEFAULT_COMP_WORDBREAKS
    end

    # Completion context variables (set during programmable completion)
    @comp_words = []      # COMP_WORDS - array of words on the command line
    @comp_cword = 0       # COMP_CWORD - index of word containing cursor
    @comp_line = ''       # COMP_LINE - current command line
    @comp_point = 0       # COMP_POINT - cursor position in COMP_LINE
    @comp_type = 0        # COMP_TYPE - type of completion (9=normal, 33=listing, 37=menu, 63=partial, 64=unmodified)
    @comp_key = 0         # COMP_KEY - key that triggered completion
    @compreply = []       # COMPREPLY - array of completion results

    class << self
      attr_accessor :comp_words, :comp_cword, :comp_line, :comp_point, :comp_type, :comp_key, :compreply
    end

    def self.set_completion_context(line:, point:, words:, cword:, type: 9, key: 9)
      # Set internal class variables
      @comp_line = line
      @comp_point = point
      @comp_words = words
      @comp_cword = cword
      @comp_type = type
      @comp_key = key
      @compreply = []

      # Expose as shell-accessible variables for programmable completion
      # COMP_WORDS - array accessible as ${COMP_WORDS[0]}, ${COMP_WORDS[@]}, etc.
      set_array('COMP_WORDS', words)

      # COMP_CWORD, COMP_LINE, COMP_POINT, COMP_TYPE, COMP_KEY - scalars
      ENV['COMP_CWORD'] = cword.to_s
      ENV['COMP_LINE'] = line
      ENV['COMP_POINT'] = point.to_s
      ENV['COMP_TYPE'] = type.to_s
      ENV['COMP_KEY'] = key.to_s

      # cur/prev - bash completion convention for current and previous words
      ENV['cur'] = words[cword] || ''
      ENV['prev'] = words[cword - 1] || '' if cword > 0

      # COMPREPLY - array that completion functions populate
      set_array('COMPREPLY', [])
    end

    def self.clear_completion_context
      # Clear internal class variables
      @comp_words = []
      @comp_cword = 0
      @comp_line = ''
      @comp_point = 0
      @comp_type = 0
      @comp_key = 0
      @compreply = []

      # Clear shell-accessible variables
      unset_array('COMP_WORDS')
      unset_array('COMPREPLY')
      ENV.delete('COMP_CWORD')
      ENV.delete('COMP_LINE')
      ENV.delete('COMP_POINT')
      ENV.delete('COMP_TYPE')
      ENV.delete('COMP_KEY')
      ENV.delete('cur')
      ENV.delete('prev')
    end

    # TMOUT - timeout for read builtin (in seconds)
    def self.tmout
      tmout_val = ENV['TMOUT']
      return nil if tmout_val.nil? || tmout_val.empty?
      tmout_val.to_f
    end

    def self.ifs
      ENV['IFS'] || DEFAULT_IFS
    end

    def self.ifs_whitespace
      # Returns the whitespace characters in IFS (space, tab, newline)
      current_ifs = ifs
      current_ifs.chars.select { |c| c == ' ' || c == "\t" || c == "\n" }.join
    end

    def self.ifs_non_whitespace
      # Returns the non-whitespace characters in IFS
      current_ifs = ifs
      current_ifs.chars.reject { |c| c == ' ' || c == "\t" || c == "\n" }.join
    end

    def self.split_by_ifs(str)
      # Split string according to IFS rules:
      # 1. Leading/trailing IFS whitespace is ignored
      # 2. Sequences of IFS whitespace act as single delimiter
      # 3. Non-whitespace IFS chars are individual delimiters (each one)
      # 4. IFS whitespace adjacent to non-whitespace IFS is ignored
      return [] if str.nil? || str.empty?

      current_ifs = ifs
      return [str] if current_ifs.empty?

      ws_chars = ifs_whitespace
      non_ws_chars = ifs_non_whitespace

      # If IFS is only whitespace, split on whitespace sequences
      if non_ws_chars.empty?
        return str.split(/[#{Regexp.escape(ws_chars)}]+/).reject(&:empty?)
      end

      # If IFS has no whitespace, split on each non-whitespace char
      if ws_chars.empty?
        return str.split(/[#{Regexp.escape(non_ws_chars)}]/, -1)
      end

      # Mixed: whitespace sequences or non-whitespace chars as delimiters
      # First strip leading/trailing IFS whitespace
      str = str.gsub(/\A[#{Regexp.escape(ws_chars)}]+|[#{Regexp.escape(ws_chars)}]+\z/, '')

      # Split on: non-ws-ifs (surrounded by optional ws) or ws sequences
      ws_pattern = "[#{Regexp.escape(ws_chars)}]*"
      non_ws_pattern = "[#{Regexp.escape(non_ws_chars)}]"
      pattern = /#{ws_pattern}#{non_ws_pattern}#{ws_pattern}|[#{Regexp.escape(ws_chars)}]+/

      str.split(pattern).reject(&:empty?)
    end

    def self.split_by_ifs_n(str, n)
      # Split string by IFS into at most n parts
      # The last part contains the remainder (preserving delimiters)
      return [] if str.nil? || str.empty?
      return [str] if n <= 1

      current_ifs = ifs
      return [str] if current_ifs.empty?

      ws_chars = ifs_whitespace
      non_ws_chars = ifs_non_whitespace

      # Strip leading IFS whitespace
      str = str.sub(/\A[#{Regexp.escape(ws_chars)}]+/, '') unless ws_chars.empty?

      parts = []
      remaining = str

      (n - 1).times do
        break if remaining.empty?

        # Find next delimiter
        if non_ws_chars.empty?
          # Only whitespace in IFS
          ws_regex = /\A(.*?)([#{Regexp.escape(ws_chars)}]+)(.*)$/m
          if match = remaining.match(ws_regex)
            parts << match[1]
            remaining = match[3]
          else
            parts << remaining
            remaining = ''
          end
        elsif ws_chars.empty?
          # Only non-whitespace in IFS
          non_ws_regex = /\A(.*?)([#{Regexp.escape(non_ws_chars)}])(.*)$/m
          if match = remaining.match(non_ws_regex)
            parts << match[1]
            remaining = match[3]
          else
            parts << remaining
            remaining = ''
          end
        else
          # Has both whitespace and non-whitespace delimiters
          ws_pattern = "[#{Regexp.escape(ws_chars)}]*"
          combined_regex = /\A(.*?)(#{ws_pattern}[#{Regexp.escape(non_ws_chars)}]#{ws_pattern}|[#{Regexp.escape(ws_chars)}]+)(.*)$/m

          if match = remaining.match(combined_regex)
            parts << match[1]
            remaining = match[3]
          else
            parts << remaining
            remaining = ''
          end
        end
      end

      # Add remaining as last part (strip trailing IFS whitespace)
      unless remaining.empty?
        remaining = remaining.sub(/[#{Regexp.escape(ws_chars)}]+\z/, '') unless ws_chars.empty?
        parts << remaining
      end

      parts
    end

    def self.join_by_ifs(words)
      # Join words using first character of IFS (for $*)
      current_ifs = ifs
      separator = current_ifs.empty? ? '' : current_ifs[0]
      words.join(separator)
    end

    # Coproc methods
    def self.coproc?(name)
      @coprocs.key?(name)
    end

    def self.get_coproc(name)
      @coprocs[name]
    end

    def self.set_coproc(name, pid:, read_fd:, write_fd:, reader:, writer:)
      @coprocs[name] = {
        pid: pid,
        read_fd: read_fd,
        write_fd: write_fd,
        reader: reader,
        writer: writer
      }
      # Store file descriptors as array (bash-compatible)
      set_array(name, [read_fd.to_s, write_fd.to_s])
      # Store PID as NAME_PID
      ENV["#{name}_PID"] = pid.to_s
    end

    def self.remove_coproc(name)
      coproc = @coprocs.delete(name)
      return unless coproc

      # Close file descriptors
      coproc[:reader]&.close rescue nil
      coproc[:writer]&.close rescue nil
      # Clean up array and PID env var
      unset_array(name)
      ENV.delete("#{name}_PID")
    end

    def self.coproc_read_fd(name)
      @coprocs.dig(name, :read_fd)
    end

    def self.coproc_write_fd(name)
      @coprocs.dig(name, :write_fd)
    end

    def self.coproc_pid(name)
      @coprocs.dig(name, :pid)
    end

    def self.coproc_reader(name)
      @coprocs.dig(name, :reader)
    end

    def self.coproc_writer(name)
      @coprocs.dig(name, :writer)
    end

    # Valid shell options with their default values and descriptions
    SHELL_OPTIONS = {
      'array_expand_once' => [false, 'only expand array subscripts once (bash 5.2+)'],
      'assoc_expand_once' => [false, 'only expand associative array subscripts once (deprecated, use array_expand_once)'],
      'autocd' => [false, 'cd to a directory when typed as command'],
      'bash_source_fullpath' => [false, 'store full pathnames in BASH_SOURCE array'],
      'cdable_vars' => [false, 'cd argument can be a variable containing a directory name'],
      'cdspell' => [false, 'correct minor spelling errors in cd'],
      'checkhash' => [false, 'check hash table before executing'],
      'checkjobs' => [false, 'check for running jobs before exit'],
      'checkwinsize' => [false, 'check window size after each command and update LINES and COLUMNS'],
      'cmdhist' => [true, 'save multi-line commands as single history entry'],
      'compat10' => [false, 'compatibility mode for rubish 1.0'],
      'compat31' => [false, 'compatibility mode for bash 3.1'],
      'compat32' => [false, 'compatibility mode for bash 3.2'],
      'compat40' => [false, 'compatibility mode for bash 4.0'],
      'compat41' => [false, 'compatibility mode for bash 4.1'],
      'compat42' => [false, 'compatibility mode for bash 4.2'],
      'compat43' => [false, 'compatibility mode for bash 4.3'],
      'compat44' => [false, 'compatibility mode for bash 4.4'],
      'compat50' => [false, 'compatibility mode for bash 5.0'],
      'compat51' => [false, 'compatibility mode for bash 5.1'],
      'compat52' => [false, 'compatibility mode for bash 5.2'],
      'compat53' => [false, 'compatibility mode for bash 5.3'],
      'compat54' => [false, 'compatibility mode for bash 5.4'],
      'compat55' => [false, 'compatibility mode for bash 5.5'],
      'complete_fullquote' => [true, 'quote all metacharacters in filename completion'],
      'direxpand' => [false, 'expand directory names during word completion'],
      'dirspell' => [false, 'correct minor spelling errors in directory names during completion'],
      'dotglob' => [false, 'include dotfiles in pathname expansion'],
      'execfail' => [false, 'do not exit non-interactive shell if exec fails'],
      'expand_aliases' => [true, 'expand aliases'],
      'extdebug' => [false, 'enable extended debugging mode'],
      'extglob' => [false, 'enable extended pattern matching'],
      'extquote' => [true, 'enable $\'...\' and $"..." quoting within ${...}'],
      'failglob' => [false, 'patterns which fail to match produce an error'],
      'force_fignore' => [true, 'apply FIGNORE to word completion'],
      'globasciiranges' => [true, 'use ASCII ordering for range expressions in bracket patterns'],
      'globskipdots' => [false, 'skip . and .. in pathname expansion'],
      'globstar' => [false, 'enable ** for recursive globbing'],
      'gnu_errfmt' => [false, 'print error messages in GNU format'],
      'histappend' => [false, 'append to history file'],
      'histreedit' => [false, 'allow re-editing of failed history substitution'],
      'histverify' => [false, 'verify history substitution before executing'],
      'hostcomplete' => [true, 'attempt hostname completion'],
      'huponexit' => [false, 'send SIGHUP to all jobs when an interactive login shell exits'],
      'inherit_errexit' => [false, 'command substitution inherits the errexit option'],
      'interactive_comments' => [true, 'allow comments in interactive shell'],
      'lastpipe' => [false, 'run last command of pipeline in current shell'],
      'lithist' => [false, 'preserve newlines in multi-line history'],
      'localvar_inherit' => [false, 'local variables inherit value from previous scope'],
      'localvar_unset' => [false, 'calling unset on local variable removes it from scope'],
      'localvar_warning' => [false, 'warn when local variable shadows variable from outer scope'],
      'login_shell' => [false, 'shell is a login shell (read-only)'],
      'mailwarn' => [false, 'warn if mail file has been accessed since last check'],
      'no_empty_cmd_completion' => [false, 'do not complete on empty command line'],
      'nocaseglob' => [false, 'case-insensitive pathname expansion'],
      'nocasematch' => [false, 'case-insensitive pattern matching'],
      'noexpand_translation' => [false, 'do not expand $"..." strings for translation'],
      'nullglob' => [false, 'patterns matching nothing expand to null'],
      'patsub_replacement' => [true, 'enable & replacement in pattern substitution'],
      'progcomp' => [true, 'enable programmable completion'],
      'progcomp_alias' => [false, 'allow programmable completion for aliases'],
      'promptvars' => [true, 'expand variables in prompt strings'],
      'restricted_shell' => [false, 'shell is restricted (read-only)'],
      'shift_verbose' => [false, 'print error if shift count exceeds positional parameters'],
      'sourcepath' => [true, 'use PATH to find sourced files'],
      'syslog_history' => [false, 'send history to syslog'],
      'varredir_close' => [false, 'close file descriptors opened by {varname} redirection'],
      'xpg_echo' => [false, 'echo expands backslash-escape sequences']
    }.freeze

    # Compatibility level options (like bash's compat31, compat32, etc.)
    COMPAT_OPTIONS = %w[compat10 compat31 compat32 compat40 compat41 compat42 compat43 compat44 compat50 compat51 compat52 compat53 compat54 compat55].freeze

    # Mapping from zsh option names to bash shopt equivalents
    # These options exist in both shells (possibly with different names)
    ZSH_TO_BASH_OPTIONS = {
      'autocd' => 'autocd',
      'auto_cd' => 'autocd',
      'cdablevars' => 'cdable_vars',
      'cdable_vars' => 'cdable_vars',
      'globdots' => 'dotglob',
      'glob_dots' => 'dotglob',
      'extendedglob' => 'extglob',
      'extended_glob' => 'extglob',
      'nullglob' => 'nullglob',
      'null_glob' => 'nullglob',
      'globstar' => 'globstar',
      'glob_star' => 'globstar',
      'nocaseglob' => 'nocaseglob',
      'nocase_glob' => 'nocaseglob',
      'histappend' => 'histappend',
      'hist_append' => 'histappend',
      'appendhistory' => 'histappend',
      'append_history' => 'histappend',
      'interactivecomments' => 'interactive_comments',
      'interactive_comments' => 'interactive_comments',
      'checkjobs' => 'checkjobs',
      'check_jobs' => 'checkjobs',
      'pipefail' => 'pipefail',
      'pipe_fail' => 'pipefail'
    }.freeze

    # Zsh-specific options (not in bash)
    # Format: option_name => [default_value, description]
    ZSH_OPTIONS = {
      # Changing Directories
      'auto_pushd' => [false, 'make cd push the old directory onto the directory stack'],
      'chase_dots' => [false, 'resolve .. in cd to physical directory'],
      'chase_links' => [false, 'resolve symbolic links in cd to physical directory'],
      'pushd_ignore_dups' => [false, 'do not push duplicate directories'],
      'pushd_minus' => [false, 'exchange +/- meanings in pushd'],
      'pushd_silent' => [false, 'do not print directory stack after pushd/popd'],
      'pushd_to_home' => [false, 'pushd with no args goes to home'],

      # Completion
      'always_to_end' => [false, 'move cursor to end after completion'],
      'auto_list' => [true, 'automatically list choices on ambiguous completion'],
      'auto_menu' => [true, 'show completion menu on successive tab'],
      'auto_param_slash' => [true, 'add trailing slash for completed directories'],
      'auto_remove_slash' => [true, 'remove trailing slash when next char is word delimiter'],
      'complete_in_word' => [false, 'complete from both ends of cursor'],
      'glob_complete' => [false, 'generate matches from glob pattern'],
      'list_ambiguous' => [true, 'list completions when ambiguous'],
      'list_packed' => [false, 'variable width completion list'],
      'list_rows_first' => [false, 'list completions in rows instead of columns'],
      'list_types' => [true, 'show file type indicator in completion list'],
      'menu_complete' => [false, 'insert first match immediately on ambiguous completion'],
      'rec_exact' => [false, 'recognize exact matches even if ambiguous'],

      # Expansion and Globbing
      'bad_pattern' => [true, 'print error on bad glob pattern'],
      'bare_glob_qual' => [true, 'allow glob qualifiers without parentheses'],
      'brace_ccl' => [false, 'expand {a-z} to a b c ... z'],
      'case_glob' => [true, 'case-sensitive globbing'],
      'case_match' => [true, 'case-sensitive pattern matching'],
      'equals' => [true, 'expand =cmd to path of cmd'],
      'extended_glob' => [false, 'enable extended glob operators'],
      'glob' => [true, 'enable globbing'],
      'glob_subst' => [false, 'treat characters from parameter expansion as glob'],
      'mark_dirs' => [false, 'append / to directories from globbing'],
      'multibyte' => [true, 'respect multibyte characters'],
      'nomatch' => [true, 'print error if glob has no matches'],
      'numeric_glob_sort' => [false, 'sort numerically when globbing'],
      'rc_expand_param' => [false, 'array expansion like rc shell'],
      'rematch_pcre' => [false, 'use PCRE for =~ operator'],
      'sh_glob' => [false, 'disable special glob characters'],
      'unset' => [false, 'treat unset variables as empty instead of error'],
      'warn_create_global' => [false, 'warn when creating global in function'],

      # History
      'bang_hist' => [true, 'enable ! history expansion'],
      'extended_history' => [false, 'save timestamp in history'],
      'hist_expire_dups_first' => [false, 'expire duplicate entries first'],
      'hist_find_no_dups' => [false, 'skip duplicates when searching history'],
      'hist_ignore_all_dups' => [false, 'remove older duplicate entries'],
      'hist_ignore_dups' => [false, 'do not record consecutive duplicates'],
      'hist_ignore_space' => [false, 'do not record entries starting with space'],
      'hist_no_functions' => [false, 'do not record function definitions'],
      'hist_no_store' => [false, 'do not record history command'],
      'hist_reduce_blanks' => [false, 'remove superfluous blanks'],
      'hist_save_no_dups' => [false, 'do not save duplicates to history file'],
      'hist_verify' => [false, 'show history expansion before executing'],
      'inc_append_history' => [false, 'append incrementally to history file'],
      'share_history' => [false, 'share history between sessions'],

      # Input/Output
      'aliases' => [true, 'enable aliases'],
      'clobber' => [true, 'allow > to overwrite existing files'],
      'correct' => [false, 'try to correct spelling of commands'],
      'correct_all' => [false, 'try to correct spelling of all arguments'],
      'flow_control' => [true, 'enable ^S/^Q flow control'],
      'ignore_eof' => [false, 'do not exit on end-of-file'],
      'hash_cmds' => [true, 'hash command locations'],
      'hash_dirs' => [true, 'hash directories containing commands'],
      'mail_warning' => [false, 'warn if mail file has been accessed'],
      'path_dirs' => [false, 'search path for / commands'],
      'print_exit_value' => [false, 'print non-zero exit values'],
      'rc_quotes' => [false, "allow '' to escape ' in single quotes"],
      'rm_star_silent' => [false, 'do not warn on rm *'],
      'rm_star_wait' => [false, 'wait before executing rm *'],
      'short_loops' => [true, 'allow short loop forms'],

      # Job Control
      'auto_continue' => [false, 'automatically send SIGCONT to disowned jobs'],
      'auto_resume' => [false, 'treat single word as resume of existing job'],
      'bg_nice' => [true, 'run background jobs at lower priority'],
      'check_running_jobs' => [false, 'check for running jobs on exit'],
      'hup' => [true, 'send SIGHUP to jobs when shell exits'],
      'long_list_jobs' => [false, 'list jobs in long format'],
      'monitor' => [true, 'enable job control'],
      'notify' => [false, 'report job status immediately'],

      # Prompting
      'prompt_bang' => [false, 'enable ! substitution in prompts'],
      'prompt_cr' => [true, 'print CR before prompt'],
      'prompt_percent' => [true, 'enable % substitution in prompts'],
      'prompt_sp' => [true, 'preserve partial line'],
      'prompt_subst' => [false, 'enable parameter expansion in prompts'],
      'transient_rprompt' => [false, 'remove right prompt after command'],

      # Scripts and Functions
      'c_bases' => [false, 'output hex/octal in C format'],
      'err_exit' => [false, 'exit on non-zero status (like set -e)'],
      'err_return' => [false, 'return from function on error'],
      'exec' => [true, 'execute commands'],
      'function_argzero' => [true, 'set $0 to function name'],
      'local_loops' => [false, 'break/continue affect only local loops'],
      'local_options' => [false, 'restore options on function return'],
      'local_traps' => [false, 'restore traps on function return'],
      'multios' => [true, 'enable multiple redirections'],
      'octal_zeroes' => [false, 'interpret leading 0 as octal'],
      'source_trace' => [false, 'print source file names'],
      'typeset_silent' => [false, 'do not print variable values in typeset'],
      'verbose' => [false, 'print shell input lines'],
      'xtrace' => [false, 'print commands before execution'],

      # Shell Emulation
      'bsd_echo' => [false, 'make echo BSD compatible'],
      'csh_junkie_loops' => [false, 'allow csh-style loop syntax'],
      'csh_nullcmd' => [false, 'do not use NULLCMD/READNULLCMD'],
      'ksh_arrays' => [false, 'array index starts at 0'],
      'ksh_autoload' => [false, 'ksh-style autoloading'],
      'ksh_option_print' => [false, 'print options ksh-style'],
      'ksh_typeset' => [false, 'ksh-style typeset behavior'],
      'posix_aliases' => [false, 'POSIX alias expansion'],
      'posix_builtins' => [false, 'POSIX builtin behavior'],
      'posix_identifiers' => [false, 'POSIX identifier rules'],
      'posix_strings' => [false, 'POSIX string behavior'],
      'posix_traps' => [false, 'POSIX trap behavior'],
      'sh_file_expansion' => [false, 'sh-style filename expansion'],
      'sh_nullcmd' => [false, 'do not use NULLCMD for empty redirections'],
      'sh_word_split' => [false, 'split unquoted parameter expansions'],
      'traps_async' => [false, 'run traps asynchronously'],

      # Zle (Zsh Line Editor)
      'beep' => [true, 'beep on errors'],
      'combining_chars' => [false, 'handle combining characters'],
      'emacs' => [false, 'use emacs keybindings'],
      'overstrike' => [false, 'start in overstrike mode'],
      'single_line_zle' => [false, 'use single line editing'],
      'vi' => [false, 'use vi keybindings'],
      'zle' => [true, 'use zsh line editor']
    }.freeze

    def self.builtin?(name)
      (COMMANDS.include?(name) || @dynamic_commands.include?(name)) && !@disabled_builtins.include?(name)
    end

    def self.builtin_exists?(name)
      COMMANDS.include?(name) || @dynamic_commands.include?(name)
    end

    def self.builtin_enabled?(name)
      (COMMANDS.include?(name) || @dynamic_commands.include?(name)) && !@disabled_builtins.include?(name)
    end

    def self.all_commands
      COMMANDS + @dynamic_commands
    end

    def self.run(name, args)
      case name
      when 'cd'
        run_cd(args)
      when 'exit'
        run_exit(args)
      when 'logout'
        run_logout(args)
      when 'jobs'
        run_jobs(args)
      when 'fg'
        run_fg(args)
      when 'bg'
        run_bg(args)
      when 'export'
        run_export(args)
      when 'pwd'
        run_pwd(args)
      when 'history'
        run_history(args)
      when 'alias'
        run_alias(args)
      when 'unalias'
        run_unalias(args)
      when 'source', '.'
        run_source(args)
      when 'shift'
        run_shift(args)
      when 'set'
        run_set(args)
      when 'return'
        run_return(args)
      when 'read'
        run_read(args)
      when 'echo'
        run_echo(args)
      when 'test', '['
        run_test(args)
      when 'break'
        run_break(args)
      when 'continue'
        run_continue(args)
      when 'pushd'
        run_pushd(args)
      when 'popd'
        run_popd(args)
      when 'dirs'
        run_dirs(args)
      when 'trap'
        run_trap(args)
      when 'getopts'
        run_getopts(args)
      when 'local'
        run_local(args)
      when 'unset'
        run_unset(args)
      when 'readonly'
        run_readonly(args)
      when 'declare', 'typeset'
        run_declare(args)
      when 'let'
        run_let(args)
      when 'printf'
        run_printf(args)
      when 'type'
        run_type(args)
      when 'which'
        run_which(args)
      when 'true', ':'
        true
      when 'false'
        false
      when 'eval'
        run_eval(args)
      when 'command'
        run_command(args)
      when 'builtin'
        run_builtin(args)
      when 'wait'
        run_wait(args)
      when 'kill'
        run_kill(args)
      when 'umask'
        run_umask(args)
      when 'exec'
        run_exec(args)
      when 'times'
        run_times(args)
      when 'hash'
        run_hash(args)
      when 'disown'
        run_disown(args)
      when 'ulimit'
        run_ulimit(args)
      when 'suspend'
        run_suspend(args)
      when 'shopt'
        run_shopt(args)
      when 'enable'
        run_enable(args)
      when 'caller'
        run_caller(args)
      when 'complete'
        run_complete(args)
      when 'compgen'
        run_compgen(args)
      when 'compopt'
        run_compopt(args)
      when 'bind'
        run_bind(args)
      when 'help'
        run_help(args)
      when 'fc'
        run_fc(args)
      when 'mapfile', 'readarray'
        run_mapfile(args)
      when 'basename'
        run_basename(args)
      when 'dirname'
        run_dirname(args)
      when 'realpath'
        run_realpath(args)
      # Bash-completion helper functions
      when '_get_comp_words_by_ref'
        run__get_comp_words_by_ref(args)
      when '_init_completion'
        run__init_completion(args)
      when '_filedir'
        run__filedir(args)
      when '_have'
        run__have(args)
      when '_split_longopt'
        run__split_longopt(args)
      when '__ltrim_colon_completions'
        run____ltrim_colon_completions(args)
      when '_variables'
        run__variables(args)
      when '_tilde'
        run__tilde(args)
      when '_quote_readline_by_ref'
        run__quote_readline_by_ref(args)
      when '_parse_help'
        run__parse_help(args)
      when '_upvars'
        run__upvars(args)
      when '_usergroup'
        run__usergroup(args)
      when 'setopt'
        run_setopt(args)
      when 'unsetopt'
        run_unsetopt(args)
      else
        # Check for dynamically loaded builtins
        if @loaded_builtins.key?(name)
          callable = @loaded_builtins[name][:callable]
          if callable.respond_to?(:call)
            callable.call(args)
          else
            false
          end
        else
          false
        end
      end
    end

    def self.run_cd(args)
      # cd [-L|-P] [dir]
      # -L: follow symbolic links (default)
      # -P: use physical directory structure (don't follow symlinks)

      # Restricted mode: cd is disabled
      if restricted_mode?
        $stderr.puts 'rubish: cd: restricted'
        return false
      end

      physical = set_option?('P')
      remaining_args = []

      args.each do |arg|
        case arg
        when '-P'
          physical = true
        when '-L'
          physical = false
        else
          remaining_args << arg
        end
      end

      dir = remaining_args.first || ENV['HOME']
      found_via_cdpath = false

      # Handle cdable_vars: if directory doesn't exist and cdable_vars is set,
      # try treating the argument as a variable name
      if dir && shopt_enabled?('cdable_vars') && !File.directory?(dir)
        var_value = ENV[dir]
        if var_value && File.directory?(var_value)
          dir = var_value
        end
      end

      # Handle cdspell: correct minor spelling errors in directory names
      if dir && shopt_enabled?('cdspell') && !File.directory?(dir)
        corrected = correct_directory_spelling(dir)
        if corrected && corrected != dir
          $stderr.puts corrected
          dir = corrected
        end
      end

      # Handle CDPATH for relative directories (not starting with / or . or ..)
      if dir && !dir.start_with?('/') && !dir.start_with?('./') && !dir.start_with?('../') && dir != '.' && dir != '..'
        # First check if directory exists relative to current directory
        unless File.directory?(dir)
          # Search CDPATH
          cdpath = ENV['CDPATH']
          if cdpath && !cdpath.empty?
            cdpath.split(':').each do |path|
              path = '.' if path.empty?  # Empty entry means current directory
              candidate = File.join(path, dir)
              if File.directory?(candidate)
                dir = candidate
                found_via_cdpath = true
                break
              end
            end
          end
        end
      end

      # Save OLDPWD before changing
      ENV['OLDPWD'] = ENV['PWD'] || Dir.pwd

      if physical
        # Resolve to physical path (no symlinks)
        target = File.realpath(File.expand_path(dir))
        Dir.chdir(target)
        ENV['PWD'] = target
      else
        Dir.chdir(dir)
        ENV['PWD'] = Dir.pwd
      end

      # Print directory when found via CDPATH
      puts ENV['PWD'] if found_via_cdpath

      true
    rescue Errno::ENOENT => e
      $stderr.puts "cd: #{e.message}"
      false
    end

    # Correct minor spelling errors in directory path for cdspell
    def self.correct_directory_spelling(path)
      # Split path into components
      components = path.split('/')
      return nil if components.empty?

      # Handle absolute vs relative paths
      if path.start_with?('/')
        current = '/'
        components.shift  # Remove empty first element from absolute path
      else
        current = '.'
      end

      corrected_components = []

      components.each do |component|
        next if component.empty?

        target = File.join(current, component)
        if File.directory?(target)
          corrected_components << component
          current = target
        else
          # Try to find a similar directory name
          correction = find_similar_directory(current, component)
          if correction
            corrected_components << correction
            current = File.join(current, correction)
          else
            # No correction found, return nil
            return nil
          end
        end
      end

      return nil if corrected_components.empty?

      if path.start_with?('/')
        '/' + corrected_components.join('/')
      else
        corrected_components.join('/')
      end
    end

    # Find a directory similar to the given name (within edit distance 1)
    def self.find_similar_directory(parent, name)
      return nil unless File.directory?(parent)

      begin
        entries = Dir.entries(parent).select { |e| e != '.' && e != '..' && File.directory?(File.join(parent, e)) }
      rescue Errno::EACCES
        return nil
      end

      # Check for exact case-insensitive match first
      entries.each do |entry|
        return entry if entry.downcase == name.downcase
      end

      # Check for edit distance 1 (transposition, deletion, insertion, substitution)
      entries.each do |entry|
        return entry if edit_distance_one?(name, entry)
      end

      nil
    end

    # Check if two strings have edit distance of 1
    def self.edit_distance_one?(s1, s2)
      len1 = s1.length
      len2 = s2.length

      # Transposition (same length, two adjacent chars swapped)
      if len1 == len2
        diffs = 0
        transposed = false
        (0...len1).each do |i|
          if s1[i] != s2[i]
            diffs += 1
            # Check for transposition
            if i + 1 < len1 && s1[i] == s2[i + 1] && s1[i + 1] == s2[i]
              transposed = true
            end
          end
        end
        return true if diffs == 1  # Single substitution
        return true if diffs == 2 && transposed  # Transposition
      end

      # Deletion (s1 is one char shorter than s2)
      if len1 == len2 - 1
        j = 0
        (0...len1).each do |i|
          j += 1 if s1[i] != s2[j]
          return false if j > i + 1
          j += 1
        end
        return true
      end

      # Insertion (s1 is one char longer than s2)
      if len1 == len2 + 1
        j = 0
        (0...len2).each do |i|
          j += 1 if s1[j] != s2[i]
          return false if j > i + 1
          j += 1
        end
        return true
      end

      false
    end

    def self.run_pushd(args)
      # pushd [-n] [+N | -N | dir]
      # -n: Suppress the normal change of directory; only manipulate the stack
      # +N: Rotate the stack so that the Nth directory (counting from left, starting at 0) is at the top
      # -N: Rotate the stack so that the Nth directory (counting from right, starting at 0) is at the top
      # dir: Push dir onto the stack and cd to it

      no_cd = false
      remaining_args = []

      args.each do |arg|
        if arg == '-n'
          no_cd = true
        else
          remaining_args << arg
        end
      end

      if remaining_args.empty?
        # Swap top two directories
        if @dir_stack.empty?
          puts 'pushd: no other directory'
          return false
        end
        current = Dir.pwd
        target = @dir_stack.shift
        @dir_stack.unshift(current)
        unless no_cd
          begin
            Dir.chdir(target)
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      elsif remaining_args.first =~ /^[+-]\d+$/
        # Stack rotation: +N or -N
        arg = remaining_args.first
        n = arg[1..].to_i
        full_stack = [Dir.pwd] + @dir_stack

        if n >= full_stack.length
          puts "pushd: #{arg}: directory stack index out of range"
          return false
        end

        if arg.start_with?('+')
          # +N: rotate left by N positions
          rotated = full_stack.rotate(n)
        else
          # -N: count from right (end of stack)
          # -0 is last element, -1 is second to last, etc.
          index = full_stack.length - 1 - n
          if index < 0
            puts "pushd: #{arg}: directory stack index out of range"
            return false
          end
          rotated = full_stack.rotate(index)
        end

        target = rotated.first
        @dir_stack = rotated[1..]

        unless no_cd
          begin
            Dir.chdir(target)
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      else
        # Push directory
        dir = remaining_args.first
        dir = File.expand_path(dir)
        current = Dir.pwd

        unless File.directory?(dir)
          puts "pushd: #{dir}: No such file or directory"
          return false
        end

        @dir_stack.unshift(current)
        unless no_cd
          begin
            Dir.chdir(dir)
          rescue Errno::ENOENT => e
            puts "pushd: #{e.message}"
            return false
          end
        end
        print_dir_stack
        true
      end
    end

    def self.run_popd(args)
      # popd [-n] [+N | -N]
      # -n: Suppress the normal change of directory; only manipulate the stack
      # +N: Remove the Nth directory (counting from left, starting at 0)
      # -N: Remove the Nth directory (counting from right, starting at 0)

      no_cd = false
      index_arg = nil

      args.each do |arg|
        if arg == '-n'
          no_cd = true
        elsif arg =~ /^[+-]\d+$/
          index_arg = arg
        else
          puts "popd: #{arg}: invalid argument"
          return false
        end
      end

      if @dir_stack.empty? && index_arg.nil?
        puts 'popd: directory stack empty'
        return false
      end

      full_stack = [Dir.pwd] + @dir_stack

      if index_arg
        n = index_arg[1..].to_i

        if index_arg.start_with?('+')
          # +N: remove Nth element from left (0 = current dir)
          index = n
        else
          # -N: remove Nth element from right (0 = last element)
          index = full_stack.length - 1 - n
        end

        if index < 0 || index >= full_stack.length
          puts "popd: #{index_arg}: directory stack index out of range"
          return false
        end

        if index == 0
          # Removing current directory - need to cd to next
          if full_stack.length < 2
            puts 'popd: directory stack empty'
            return false
          end
          target = full_stack[1]
          @dir_stack = full_stack[2..] || []
          unless no_cd
            begin
              Dir.chdir(target)
            rescue Errno::ENOENT => e
              puts "popd: #{e.message}"
              return false
            end
          end
        else
          # Removing from stack (not current dir)
          full_stack.delete_at(index)
          @dir_stack = full_stack[1..] || []
        end
      else
        # Default: pop top of stack and cd there
        if @dir_stack.empty?
          puts 'popd: directory stack empty'
          return false
        end

        target = @dir_stack.shift
        unless no_cd
          begin
            Dir.chdir(target)
          rescue Errno::ENOENT => e
            puts "popd: #{e.message}"
            return false
          end
        end
      end

      print_dir_stack
      true
    end

    def self.run_dirs(args)
      print_dir_stack
      true
    end

    def self.print_dir_stack
      stack = [Dir.pwd] + @dir_stack
      puts stack.map { |d| d.sub(ENV['HOME'], '~') }.join(' ')
    end

    def self.clear_dir_stack
      @dir_stack.clear
    end

    # Signal name mapping
    # Map signal names/numbers to canonical signal names
    # Includes both short names (HUP) and long names (SIGHUP)
    SIGNALS = {
      # Pseudo-signals (shell-specific, not OS signals)
      'EXIT' => 0,
      'ERR' => 'ERR',        # Triggered on command failure
      'DEBUG' => 'DEBUG',    # Triggered before each command
      'RETURN' => 'RETURN',  # Triggered when function/sourced script returns

      # Standard signals with numeric mappings
      '0' => 0,              # EXIT
      '1' => 'HUP',  'HUP' => 'HUP',   'SIGHUP' => 'HUP',
      '2' => 'INT',  'INT' => 'INT',   'SIGINT' => 'INT',
      '3' => 'QUIT', 'QUIT' => 'QUIT', 'SIGQUIT' => 'QUIT',
      '4' => 'ILL',  'ILL' => 'ILL',   'SIGILL' => 'ILL',
      '5' => 'TRAP', 'TRAP' => 'TRAP', 'SIGTRAP' => 'TRAP',
      '6' => 'ABRT', 'ABRT' => 'ABRT', 'SIGABRT' => 'ABRT', 'IOT' => 'ABRT', 'SIGIOT' => 'ABRT',
      '7' => 'EMT',  'EMT' => 'EMT',   'SIGEMT' => 'EMT',
      '8' => 'FPE',  'FPE' => 'FPE',   'SIGFPE' => 'FPE',
      '9' => 'KILL', 'KILL' => 'KILL', 'SIGKILL' => 'KILL',
      '10' => 'BUS', 'BUS' => 'BUS',   'SIGBUS' => 'BUS',
      '11' => 'SEGV', 'SEGV' => 'SEGV', 'SIGSEGV' => 'SEGV',
      '12' => 'SYS', 'SYS' => 'SYS',   'SIGSYS' => 'SYS',
      '13' => 'PIPE', 'PIPE' => 'PIPE', 'SIGPIPE' => 'PIPE',
      '14' => 'ALRM', 'ALRM' => 'ALRM', 'SIGALRM' => 'ALRM',
      '15' => 'TERM', 'TERM' => 'TERM', 'SIGTERM' => 'TERM',
      '16' => 'URG', 'URG' => 'URG',   'SIGURG' => 'URG',
      '17' => 'STOP', 'STOP' => 'STOP', 'SIGSTOP' => 'STOP',
      '18' => 'TSTP', 'TSTP' => 'TSTP', 'SIGTSTP' => 'TSTP',
      '19' => 'CONT', 'CONT' => 'CONT', 'SIGCONT' => 'CONT',
      '20' => 'CHLD', 'CHLD' => 'CHLD', 'SIGCHLD' => 'CHLD', 'CLD' => 'CHLD', 'SIGCLD' => 'CHLD',
      '21' => 'TTIN', 'TTIN' => 'TTIN', 'SIGTTIN' => 'TTIN',
      '22' => 'TTOU', 'TTOU' => 'TTOU', 'SIGTTOU' => 'TTOU',
      '23' => 'IO',   'IO' => 'IO',     'SIGIO' => 'IO', 'POLL' => 'IO', 'SIGPOLL' => 'IO',
      '24' => 'XCPU', 'XCPU' => 'XCPU', 'SIGXCPU' => 'XCPU',
      '25' => 'XFSZ', 'XFSZ' => 'XFSZ', 'SIGXFSZ' => 'XFSZ',
      '26' => 'VTALRM', 'VTALRM' => 'VTALRM', 'SIGVTALRM' => 'VTALRM',
      '27' => 'PROF', 'PROF' => 'PROF', 'SIGPROF' => 'PROF',
      '28' => 'WINCH', 'WINCH' => 'WINCH', 'SIGWINCH' => 'WINCH',
      '29' => 'INFO', 'INFO' => 'INFO', 'SIGINFO' => 'INFO',
      '30' => 'USR1', 'USR1' => 'USR1', 'SIGUSR1' => 'USR1',
      '31' => 'USR2', 'USR2' => 'USR2', 'SIGUSR2' => 'USR2'
    }.freeze

    # Signals that cannot be trapped (for error messages)
    UNTRAPABLE_SIGNALS = %w[KILL STOP].freeze

    def self.run_trap(args)
      if args.empty?
        # List all traps
        @traps.each do |sig, cmd|
          sig_name = sig == 0 ? 'EXIT' : sig
          puts "trap -- #{cmd.inspect} #{sig_name}"
        end
        return true
      end

      # trap -l: list signal names (bash-style format)
      if args.first == '-l'
        # Get unique signals sorted by number, format like bash: " 1) HUP  2) INT ..."
        signals = Signal.list.reject { |k, _| k == 'EXIT' }  # EXIT is 0, handled specially
        by_num = signals.group_by { |_, v| v }.transform_values { |pairs| pairs.map(&:first).min }
        sorted = by_num.sort_by { |num, _| num }

        # Print in columns like bash
        col = 0
        sorted.each do |num, name|
          print format('%2d) %-8s', num, name)
          col += 1
          if col >= 5
            puts
            col = 0
          end
        end
        puts if col > 0
        return true
      end

      # trap -p [signal...]: print trap commands
      if args.first == '-p'
        signals = args[1..] || []
        if signals.empty?
          @traps.each do |sig, cmd|
            sig_name = sig == 0 ? 'EXIT' : sig
            puts "trap -- #{cmd.inspect} #{sig_name}"
          end
        else
          signals.each do |sig_arg|
            sig = normalize_signal(sig_arg)
            next unless sig

            if @traps.key?(sig)
              sig_name = sig == 0 ? 'EXIT' : sig
              puts "trap -- #{@traps[sig].inspect} #{sig_name}"
            end
          end
        end
        return true
      end

      # trap command signal [signal...]
      # trap '' signal - ignore signal
      # trap - signal - reset to default
      # trap -- command signal - use -- to separate options from command
      # Skip -- if present (end of options marker)
      if args.first == '--'
        args = args[1..]
      end
      command = args.first
      signals = args[1..]

      if signals.nil? || signals.empty?
        puts 'trap: usage: trap [-lp] [[command] signal_spec ...]'
        return false
      end

      signals.each do |sig_arg|
        sig = normalize_signal(sig_arg)
        unless sig
          puts "trap: #{sig_arg}: invalid signal specification"
          next
        end

        if command == '-'
          # Reset to default
          reset_trap(sig)
        elsif command.empty? || command == ''
          # Ignore signal
          set_trap(sig, '')
        else
          # Set trap
          set_trap(sig, command)
        end
      end

      true
    end

    def self.normalize_signal(sig_arg)
      sig_str = sig_arg.to_s

      # Look up in SIGNALS hash (handles both numeric and named signals)
      sig_upper = sig_str.upcase
      result = SIGNALS[sig_upper]
      return result if result

      # For pure numeric input not in SIGNALS, return as integer
      if sig_str =~ /\A\d+\z/
        return sig_str.to_i
      end

      nil
    end

    # Pseudo-signals that are not real OS signals
    PSEUDO_SIGNALS = [0, 'ERR', 'DEBUG', 'RETURN'].freeze

    def self.set_trap(sig, command)
      # KILL and STOP cannot be trapped or ignored
      sig_name = sig.is_a?(Integer) ? nil : sig.to_s.upcase
      if UNTRAPABLE_SIGNALS.include?(sig_name)
        puts "trap: #{sig_name}: cannot be trapped"
        return false
      end

      # Store the trap command
      @traps[sig] = command

      # Pseudo-signals are handled by the shell, not the OS
      return true if PSEUDO_SIGNALS.include?(sig)

      # Save original handler if not already saved
      @original_traps[sig] ||= Signal.trap(sig, 'DEFAULT') rescue nil

      if command.empty?
        # Ignore the signal
        Signal.trap(sig, 'IGNORE')
      else
        # Set up the handler
        # Capture signal name for RUBISH_TRAPSIG/BASH_TRAPSIG
        sig_name = sig.is_a?(Integer) ? Signal.signame(sig) : sig.to_s.sub(/^SIG/, '')
        Signal.trap(sig) do
          @current_trapsig = sig_name
          begin
            @executor&.call(command) if @executor
          ensure
            @current_trapsig = ''
          end
        end
      end
      true
    rescue ArgumentError => e
      puts "trap: #{e.message}"
      false
    end

    def self.reset_trap(sig)
      @traps.delete(sig)

      # Pseudo-signals have no OS signal to reset
      return if PSEUDO_SIGNALS.include?(sig)

      # Restore original handler
      if @original_traps.key?(sig)
        Signal.trap(sig, @original_traps.delete(sig) || 'DEFAULT')
      else
        Signal.trap(sig, 'DEFAULT')
      end
    rescue ArgumentError => e
      puts "trap: #{e.message}"
    end

    def self.run_exit_traps
      return unless @traps.key?(0)

      @current_trapsig = 'EXIT'
      begin
        @executor&.call(@traps[0]) if @executor
      ensure
        @current_trapsig = ''
      end
    end

    @in_err_trap = false

    def self.run_err_trap
      return unless @traps.key?('ERR')
      return if @in_err_trap  # Prevent recursion

      @in_err_trap = true
      @current_trapsig = 'ERR'
      begin
        @executor&.call(@traps['ERR']) if @executor
      ensure
        @in_err_trap = false
        @current_trapsig = ''
      end
    end

    def self.err_trap_set?
      @traps.key?('ERR') && !@traps['ERR'].empty?
    end

    def self.save_and_clear_err_trap
      # Save ERR trap and clear it (for functions/subshells when errtrace is off)
      saved = @traps.delete('ERR')
      saved
    end

    def self.restore_err_trap(saved)
      # Restore a previously saved ERR trap
      if saved
        @traps['ERR'] = saved
      end
    end

    @in_debug_trap = false

    def self.run_debug_trap
      return unless @traps.key?('DEBUG')
      return if @in_debug_trap  # Prevent recursion

      @in_debug_trap = true
      @current_trapsig = 'DEBUG'
      begin
        @executor&.call(@traps['DEBUG']) if @executor
      ensure
        @in_debug_trap = false
        @current_trapsig = ''
      end
    end

    def self.debug_trap_set?
      @traps.key?('DEBUG') && !@traps['DEBUG'].empty?
    end

    @in_return_trap = false

    def self.run_return_trap
      return unless @traps.key?('RETURN')
      return if @in_return_trap  # Prevent recursion

      @in_return_trap = true
      @current_trapsig = 'RETURN'
      begin
        @executor&.call(@traps['RETURN']) if @executor
      ensure
        @in_return_trap = false
        @current_trapsig = ''
      end
    end

    def self.return_trap_set?
      @traps.key?('RETURN') && !@traps['RETURN'].empty?
    end

    def self.save_and_clear_functrace_traps
      # Save DEBUG and RETURN traps and clear them (for functions when functrace is off)
      saved = {}
      saved['DEBUG'] = @traps.delete('DEBUG') if @traps.key?('DEBUG')
      saved['RETURN'] = @traps.delete('RETURN') if @traps.key?('RETURN')
      saved.empty? ? nil : saved
    end

    def self.restore_functrace_traps(saved)
      # Restore previously saved DEBUG and RETURN traps
      return unless saved

      @traps['DEBUG'] = saved['DEBUG'] if saved['DEBUG']
      @traps['RETURN'] = saved['RETURN'] if saved['RETURN']
    end

    def self.clear_traps
      @traps.each_key do |sig|
        reset_trap(sig) unless PSEUDO_SIGNALS.include?(sig)
      end
      @traps.clear
      @original_traps.clear
    end

    def self.run_getopts(args)
      # getopts optstring name [args...]
      # Returns true if option found, false when done
      if args.length < 2
        puts 'getopts: usage: getopts optstring name [arg ...]'
        return false
      end

      optstring = args[0]
      varname = args[1]

      # Get arguments to parse - either from args or positional params
      if args.length > 2
        parse_args = args[2..]
      else
        parse_args = @positional_params_getter&.call || []
      end

      # Get current OPTIND (1-based index)
      optind = (ENV['OPTIND'] || '1').to_i

      # Check if we're done
      if optind > parse_args.length
        ENV[varname] = '?'
        return false
      end

      # Get current argument
      arg = parse_args[optind - 1]

      # Check if it's an option
      if arg.nil? || arg == '--' || !arg.start_with?('-') || arg == '-'
        ENV[varname] = '?'
        return false
      end

      # Handle -- to stop option processing
      if arg == '--'
        ENV['OPTIND'] = (optind + 1).to_s
        ENV[varname] = '?'
        return false
      end

      # Get the current character position within the option group
      # OPTPOS tracks position in grouped options like -abc
      optpos = (ENV['_OPTPOS'] || '1').to_i

      opt_char = arg[optpos]

      # Check if this is a valid option
      opt_idx = optstring.index(opt_char)
      silent_errors = optstring.start_with?(':')
      # OPTERR controls whether error messages are printed (default 1 = print errors)
      # When OPTERR=0, suppress error messages (but silent_errors from ':' prefix still affects OPTARG behavior)
      opterr = ENV['OPTERR'] != '0'

      if opt_idx.nil?
        # Invalid option
        ENV[varname] = '?'
        ENV['OPTARG'] = opt_char if silent_errors
        unless silent_errors || !opterr
          puts "getopts: illegal option -- #{opt_char}"
        end
        # Move to next character or next argument
        if optpos + 1 < arg.length
          ENV['_OPTPOS'] = (optpos + 1).to_s
        else
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        end
        return true
      end

      # Check if option requires an argument
      requires_arg = optstring[opt_idx + 1] == ':'

      if requires_arg
        # Check for argument
        if optpos + 1 < arg.length
          # Argument is rest of current arg (e.g., -ovalue)
          ENV['OPTARG'] = arg[(optpos + 1)..]
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        elsif optind < parse_args.length
          # Argument is next arg
          ENV['OPTARG'] = parse_args[optind]
          ENV['OPTIND'] = (optind + 2).to_s
          ENV['_OPTPOS'] = '1'
        else
          # Missing argument
          if silent_errors
            ENV[varname] = ':'
            ENV['OPTARG'] = opt_char
          else
            ENV[varname] = '?'
            if opterr
              puts "getopts: option requires an argument -- #{opt_char}"
            end
          end
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
          return true
        end
      else
        # No argument required
        ENV.delete('OPTARG')
        # Move to next character or next argument
        if optpos + 1 < arg.length
          ENV['_OPTPOS'] = (optpos + 1).to_s
        else
          ENV['OPTIND'] = (optind + 1).to_s
          ENV['_OPTPOS'] = '1'
        end
      end

      ENV[varname] = opt_char
      true
    end

    def self.reset_getopts
      ENV['OPTIND'] = '1'
      ENV['_OPTPOS'] = '1'
      ENV.delete('OPTARG')
    end

    def self.run_local(args)
      # local [-n] var=value or local var
      # -n: create a nameref (reference to another variable)
      # Only valid inside a function (when scope stack is not empty)
      if @local_scope_stack.empty?
        $stderr.puts 'local: can only be used in a function'
        return false
      end

      current_scope = @local_scope_stack.last
      nameref_mode = false
      remaining_args = []

      # Parse options
      args.each do |arg|
        if arg == '-n'
          nameref_mode = true
        elsif arg == '--'
          # End of options, rest are variable names
          next
        elsif arg.start_with?('-') && !arg.include?('=')
          # Unknown option
          $stderr.puts "local: #{arg}: invalid option"
          return false
        else
          remaining_args << arg
        end
      end

      remaining_args.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
          # Check if readonly
          if readonly?(name)
            $stderr.puts "local: #{name}: readonly variable"
            next
          end

          if nameref_mode
            # Create a local nameref
            # Save original nameref state if not already in this scope
            unless current_scope.key?(name)
              warn_shadow(name) if shopt_enabled?('localvar_warning') && (ENV.key?(name) || nameref?(name))
              # Store both the original ENV value and nameref state
              current_scope[name] = {
                env_value: ENV.key?(name) ? ENV[name] : :unset,
                nameref_target: nameref?(name) ? get_nameref_target(name) : nil
              }
            end
            # Set up the nameref
            set_nameref(name, value)
            # Don't set ENV for nameref - the nameref points to target
          else
            # Save original value if not already in this scope
            unless current_scope.key?(name)
              # Warn if shadowing a variable from outer scope
              warn_shadow(name) if shopt_enabled?('localvar_warning') && ENV.key?(name)
              current_scope[name] = ENV.key?(name) ? ENV[name] : :unset
            end
            ENV[name] = value
          end
        else
          # Just declare as local without value
          name = arg
          unless current_scope.key?(name)
            # Warn if shadowing a variable from outer scope
            warn_shadow(name) if shopt_enabled?('localvar_warning') && (ENV.key?(name) || (nameref_mode && nameref?(name)))
            if nameref_mode
              current_scope[name] = {
                env_value: ENV.key?(name) ? ENV[name] : :unset,
                nameref_target: nameref?(name) ? get_nameref_target(name) : nil
              }
            else
              current_scope[name] = ENV.key?(name) ? ENV[name] : :unset
            end
          end

          if nameref_mode
            # Create nameref without target (will be set later via assignment)
            # For now, just mark it as a nameref with nil target
            @var_attributes[name] ||= Set.new
            @var_attributes[name] << :nameref
          else
            # localvar_inherit: inherit value and attributes from outer scope
            if shopt_enabled?('localvar_inherit')
              # Keep the inherited value (already in ENV if it exists)
              # Also inherit variable attributes if present
              # (attributes are already global, so nothing more to do for value)
            else
              # Without localvar_inherit, local var without value creates unset variable
              # This is standard bash behavior
              ENV.delete(name)
            end
          end
        end
      end

      true
    end

    def self.push_local_scope
      @local_scope_stack.push({})
    end

    def self.pop_local_scope
      return if @local_scope_stack.empty?

      scope = @local_scope_stack.pop
      # Restore original values
      scope.each do |name, original_value|
        if original_value.is_a?(Hash)
          # This was a local nameref - restore both ENV and nameref state
          env_val = original_value[:env_value]
          nameref_target = original_value[:nameref_target]

          # First, remove the current nameref
          unset_nameref(name)

          # Restore original ENV value
          if env_val == :unset
            ENV.delete(name)
          else
            ENV[name] = env_val
          end

          # Restore original nameref if there was one
          if nameref_target
            set_nameref(name, nameref_target)
          end
        elsif original_value == :unset
          ENV.delete(name)
        else
          ENV[name] = original_value
        end
      end
    end

    def self.in_function?
      !@local_scope_stack.empty?
    end

    def self.clear_local_scopes
      @local_scope_stack.clear
    end

    def self.warn_shadow(name)
      # Print warning to stderr when local variable shadows outer scope variable
      $stderr.puts "local: warning: #{name}: shadows variable in outer scope"
    end

    def self.run_unset(args)
      # unset [-fv] name [name ...]
      # -f: treat names as function names
      # -v: treat names as variable names (default)
      mode = :variable  # default mode

      if args.empty?
        puts 'unset: usage: unset [-f] [-v] name [name ...]'
        return false
      end

      names = []
      args.each do |arg|
        case arg
        when '-f'
          mode = :function
        when '-v'
          mode = :variable
        when '-fv', '-vf'
          # Last one wins in bash, but typically -v is ignored when -f present
          mode = :function
        else
          names << arg
        end
      end

      if names.empty?
        puts 'unset: usage: unset [-f] [-v] name [name ...]'
        return false
      end

      names.each do |name|
        if mode == :function
          # Remove function
          @function_remover&.call(name)
        else
          # Check if readonly
          if readonly?(name)
            puts "unset: #{name}: readonly variable"
            next
          end

          # localvar_unset: when unsetting a local variable, remove it from local scope
          # and restore the outer scope's value
          if shopt_enabled?('localvar_unset') && !@local_scope_stack.empty?
            current_scope = @local_scope_stack.last
            if current_scope.key?(name)
              # Remove from local scope and restore original value
              original_value = current_scope.delete(name)
              if original_value == :unset
                ENV.delete(name)
              else
                ENV[name] = original_value
              end
              next
            end
          end

          # Special handling for BASH_ARGV0: loses special properties when unset
          if name == 'BASH_ARGV0'
            @bash_argv0_unsetter&.call
          end

          # Standard behavior: just remove from environment
          ENV.delete(name)
        end
      end

      true
    end

    def self.run_readonly(args)
      # readonly [-p] [name[=value] ...]
      # -p: print all readonly variables in reusable format

      if args.empty? || args == ['-p']
        # List all readonly variables
        @readonly_vars.each do |name, _|
          value = ENV[name]
          if value
            puts "readonly #{name}=#{value.inspect}"
          else
            puts "readonly #{name}"
          end
        end
        return true
      end

      # Filter out -p flag
      names = args.reject { |a| a == '-p' }

      names.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
          # Check if already readonly with different value
          if @readonly_vars.key?(name) && ENV[name] != value
            puts "readonly: #{name}: readonly variable"
            next
          end
          ENV[name] = value
          @readonly_vars[name] = true
        else
          # Mark existing variable as readonly
          @readonly_vars[arg] = true
        end
      end

      true
    end

    def self.readonly?(name)
      @readonly_vars.key?(name)
    end

    def self.clear_readonly_vars
      @readonly_vars.clear
    end

    def self.exported?(name)
      @var_attributes[name]&.include?(:export)
    end

    def self.run_declare(args)
      # declare [-aAfFgIilnrtux] [-p] [name[=value] ...]
      # -a: indexed array
      # -A: associative array
      # -f: restrict to functions (show function definitions)
      # -F: restrict to functions (show function names only)
      # -g: global variable (in functions, declare creates local vars by default)
      # -I: inherit attributes from variable with same name at previous scope
      # -i: integer attribute (arithmetic evaluation)
      # -l: lowercase attribute
      # -n: nameref attribute (variable is a reference to another variable)
      # -r: readonly attribute
      # -t: trace attribute (DEBUG/RETURN traps inherited by functions)
      # -u: uppercase attribute
      # -x: export attribute
      # -p: print declarations
      # +attr: remove attribute

      # Parse options
      print_mode = false
      array_mode = nil  # :indexed or :associative
      function_mode = false  # -f: show function definitions
      function_names_only = false  # -F: show function names only
      global_mode = false
      inherit_mode = false  # -I: inherit attributes from previous scope
      nameref_mode = false
      add_attrs = Set.new
      remove_attrs = Set.new
      names = []

      args.each do |arg|
        if arg.start_with?('-')
          if arg == '-p'
            print_mode = true
          else
            # Parse attribute flags
            arg[1..].each_char do |c|
              case c
              when 'a' then array_mode = :indexed
              when 'A' then array_mode = :associative
              when 'f' then function_mode = true
              when 'F' then function_names_only = true
              when 'g' then global_mode = true
              when 'I' then inherit_mode = true
              when 'i' then add_attrs << :integer
              when 'l' then add_attrs << :lowercase
              when 'n' then nameref_mode = true; add_attrs << :nameref
              when 'r' then add_attrs << :readonly
              when 't' then add_attrs << :trace
              when 'u' then add_attrs << :uppercase
              when 'x' then add_attrs << :export
              when 'p' then print_mode = true
              end
            end
          end
        elsif arg.start_with?('+')
          # Remove attributes
          arg[1..].each_char do |c|
            case c
            when 'i' then remove_attrs << :integer
            when 'l' then remove_attrs << :lowercase
            when 'n' then remove_attrs << :nameref
            when 't' then remove_attrs << :trace
            when 'u' then remove_attrs << :uppercase
            when 'x' then remove_attrs << :export
            # Note: can't remove readonly
            end
          end
        else
          names << arg
        end
      end

      # Handle array declarations
      if array_mode && !print_mode
        names.each do |name|
          var_name = name.split('=').first
          if array_mode == :associative
            declare_assoc_array(var_name)
          else
            set_array(var_name, []) unless array?(var_name)
          end
        end
        return true if add_attrs.empty? && remove_attrs.empty?
      end

      # Handle function listing (-f or -F)
      if function_mode || function_names_only
        return print_functions(names, function_names_only)
      end

      # Print mode with no names: show all declared variables
      if print_mode && names.empty?
        print_all_declarations(add_attrs)
        return true
      end

      # Print mode with names: show specific declarations
      if print_mode && names.any?
        names.each do |name|
          var_name = name.split('=', 2).first
          print_declaration(var_name)
        end
        return true
      end

      # No names and no attrs: list all
      if names.empty? && add_attrs.empty? && remove_attrs.empty?
        print_all_declarations(Set.new)
        return true
      end

      # Process each name
      names.each do |arg|
        if arg.include?('=')
          name, value = arg.split('=', 2)
        else
          name = arg
          value = nil
        end

        # Check readonly
        if readonly?(name) && value
          puts "declare: #{name}: readonly variable"
          next
        end

        # Track in local scope if inside a function and -g not specified
        # This makes declare behave like local by default in functions
        if in_function? && !global_mode
          current_scope = @local_scope_stack.last
          unless current_scope.key?(name)
            current_scope[name] = ENV.key?(name) ? ENV[name] : :unset
          end
        end

        # Handle -I: inherit attributes and value from previous scope
        if inherit_mode && in_function?
          # Copy existing attributes if variable exists
          if @var_attributes[name]
            add_attrs = add_attrs | @var_attributes[name]
          end
          # Inherit value if not specified and variable exists
          if value.nil? && ENV.key?(name)
            value = ENV[name]
          end
        end

        # Initialize attributes set for this variable
        @var_attributes[name] ||= Set.new

        # Add new attributes
        add_attrs.each { |attr| @var_attributes[name] << attr }

        # Remove attributes (except readonly)
        remove_attrs.each { |attr| @var_attributes[name].delete(attr) }

        # Handle nameref attribute
        if add_attrs.include?(:nameref)
          if value
            # Set the nameref to point to the target variable
            @namerefs[name] = value
          end
        end

        # Handle removing nameref attribute
        if remove_attrs.include?(:nameref)
          @namerefs.delete(name)
        end

        # Handle readonly attribute
        if add_attrs.include?(:readonly)
          @readonly_vars[name] = true
        end

        # Handle export attribute
        if add_attrs.include?(:export)
          # Variable is marked for export (already in ENV)
        end

        # Set value if provided (but not for namerefs - value is the target name)
        if value && !nameref_mode
          value = apply_attributes(name, value)
          ENV[name] = value
        end
      end

      true
    end

    # Strip surrounding quotes from a value (single or double)
    def self.strip_quotes(value)
      return value if value.nil? || value.empty?

      # $'...' ANSI-C quoting
      if value.start_with?("$'") && value.end_with?("'")
        return process_escape_sequences(value[2...-1])
      end

      # Single quotes
      if value.start_with?("'") && value.end_with?("'") && value.length >= 2
        return value[1...-1]
      end

      # Double quotes
      if value.start_with?('"') && value.end_with?('"') && value.length >= 2
        return value[1...-1]
      end

      value
    end

    def self.apply_attributes(name, value)
      attrs = @var_attributes[name] || Set.new

      # Apply integer attribute
      if attrs.include?(:integer)
        # Evaluate as arithmetic expression
        begin
          # Simple arithmetic evaluation
          result = eval(value.gsub(/[a-zA-Z_][a-zA-Z0-9_]*/) { |var| ENV[var] || '0' })
          value = result.to_s
        rescue StandardError
          value = '0'
        end
      end

      # Apply case attributes (lowercase takes precedence if both set)
      if attrs.include?(:lowercase)
        value = value.downcase
      elsif attrs.include?(:uppercase)
        value = value.upcase
      end

      value
    end

    def self.set_var_with_attributes(name, value)
      # If it's a nameref, set the target variable instead
      if nameref?(name)
        target = resolve_nameref(name)
        return if target.nil?
        name = target
      end

      # Apply attributes when setting a variable
      if @var_attributes[name]
        value = apply_attributes(name, value)
      end
      ENV[name] = value
    end

    def self.print_declaration(name)
      attrs = @var_attributes[name] || Set.new
      flags = +''
      flags << 'i' if attrs.include?(:integer)
      flags << 'l' if attrs.include?(:lowercase)
      flags << 'n' if attrs.include?(:nameref)
      flags << 'r' if readonly?(name)
      flags << 't' if attrs.include?(:trace)
      flags << 'u' if attrs.include?(:uppercase)
      flags << 'x' if attrs.include?(:export)

      # For namerefs, show the target variable name
      if attrs.include?(:nameref)
        target = @namerefs[name]
        if flags.empty?
          if target
            puts "declare -- #{name}=#{target.inspect}"
          else
            puts "declare -- #{name}"
          end
        else
          if target
            puts "declare -#{flags} #{name}=#{target.inspect}"
          else
            puts "declare -#{flags} #{name}"
          end
        end
      else
        value = ENV[name]
        if flags.empty?
          if value
            puts "declare -- #{name}=#{value.inspect}"
          else
            puts "declare -- #{name}"
          end
        else
          if value
            puts "declare -#{flags} #{name}=#{value.inspect}"
          else
            puts "declare -#{flags} #{name}"
          end
        end
      end
    end

    def self.print_all_declarations(filter_attrs)
      # Collect all variables with attributes
      vars_to_print = Set.new

      @var_attributes.each_key { |name| vars_to_print << name }
      @readonly_vars.each_key { |name| vars_to_print << name }
      @namerefs.each_key { |name| vars_to_print << name }

      vars_to_print.each do |name|
        attrs = @var_attributes[name] || Set.new
        attrs = attrs.dup
        attrs << :readonly if readonly?(name)
        attrs << :nameref if nameref?(name)

        # Filter by attributes if specified
        if filter_attrs.empty? || filter_attrs.subset?(attrs)
          print_declaration(name)
        end
      end
    end

    def self.print_functions(names, names_only)
      # Get all functions via callback
      functions = @function_lister&.call || {}

      if names.empty?
        # List all functions
        functions.each do |name, info|
          print_function(name, info, names_only)
        end
      else
        # List specific functions
        names.each do |name|
          info = @function_getter&.call(name)
          if info
            print_function(name, info, names_only)
          else
            puts "declare: #{name}: not found"
            return false
          end
        end
      end
      true
    end

    def self.print_function(name, info, names_only)
      if names_only
        # -F: just print the name (optionally with file info)
        # extdebug: when enabled, output in bash format "funcname lineno filename"
        if shopt_enabled?('extdebug') && info[:file]
          # Use line number if available, otherwise 0 as placeholder
          lineno = info[:lineno] || 0
          puts "#{name} #{lineno} #{info[:file]}"
        elsif info[:file]
          puts "declare -f #{name}  # defined in #{info[:file]}"
        else
          puts "declare -f #{name}"
        end
      else
        # -f: print full definition
        source = info[:source] || '# (source not available)'
        puts "#{name}() {"
        source.each_line do |line|
          puts "    #{line}"
        end
        puts '}'
      end
    end

    def self.get_var_attributes(name)
      @var_attributes[name] || Set.new
    end

    def self.has_attribute?(name, attr)
      (@var_attributes[name] || Set.new).include?(attr)
    end

    def self.mark_exported(name)
      @var_attributes[name] ||= Set.new
      @var_attributes[name] << :export
    end

    def self.clear_var_attributes
      @var_attributes.clear
    end

    def self.run_let(args)
      # let expression [expression ...]
      # Evaluates arithmetic expressions
      # Returns 0 (true) if last expression is non-zero, 1 (false) if zero

      if args.empty?
        puts 'let: usage: let expression [expression ...]'
        return false
      end

      last_result = 0

      args.each do |expr|
        last_result = evaluate_arithmetic(expr)
      end

      # Return true if last result is non-zero (shell convention)
      last_result != 0
    end

    def self.evaluate_arithmetic(expr)
      # Handle assignment operators (but not ==, !=, <=, >=)
      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\s*([\+\-\*\/%]?=)(?!=)\s*(.+)\z/
        var_name = $1
        operator = $2
        value_expr = $3

        # Check readonly
        if readonly?(var_name)
          puts "let: #{var_name}: readonly variable"
          return 0
        end

        # Evaluate the right side
        value = evaluate_arithmetic_expr(value_expr)

        if operator == '='
          # Simple assignment
          ENV[var_name] = value.to_s
        else
          # Compound assignment (+=, -=, *=, /=, %=)
          current = (ENV[var_name] || '0').to_i
          case operator
          when '+='
            ENV[var_name] = (current + value).to_s
          when '-='
            ENV[var_name] = (current - value).to_s
          when '*='
            ENV[var_name] = (current * value).to_s
          when '/='
            ENV[var_name] = (value.zero? ? 0 : current / value).to_s
          when '%='
            ENV[var_name] = (value.zero? ? 0 : current % value).to_s
          end
        end

        return ENV[var_name].to_i
      end

      # Handle increment/decrement operators
      if expr =~ /\A\+\+([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-increment
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i + 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A--([a-zA-Z_][a-zA-Z0-9_]*)\z/
        # Pre-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        val = (ENV[var_name] || '0').to_i - 1
        ENV[var_name] = val.to_s
        return val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\+\+\z/
        # Post-increment
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val + 1).to_s
        return old_val
      end

      if expr =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)--\z/
        # Post-decrement
        var_name = $1
        return 0 if readonly?(var_name)
        old_val = (ENV[var_name] || '0').to_i
        ENV[var_name] = (old_val - 1).to_s
        return old_val
      end

      # Just evaluate the expression
      evaluate_arithmetic_expr(expr)
    end

    def self.evaluate_arithmetic_expr(expr)
      # Replace variable references with their values
      # Handle $VAR, ${VAR}, and bare variable names
      expanded = expr.gsub(/\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
        if $1
          # ${VAR} form
          (ENV[$1] || '0')
        elsif $2
          # $VAR form
          (ENV[$2] || '0')
        elsif $3
          # Plain variable name - in arithmetic context, unset vars default to 0
          (ENV[$3] || '0')
        else
          match
        end
      end

      # Handle comparison operators (convert to Ruby equivalents)
      expanded = expanded.gsub('==', '==')
      expanded = expanded.gsub('!=', '!=')
      expanded = expanded.gsub('<=', '<=')
      expanded = expanded.gsub('>=', '>=')

      # Handle logical operators
      expanded = expanded.gsub('&&', ' && ')
      expanded = expanded.gsub('||', ' || ')
      expanded = expanded.gsub(/!(?!=)/, ' !')

      # Handle ternary operator
      expanded = expanded.gsub('?', ' ? ').gsub(':', ' : ')

      # Evaluate safely
      begin
        result = eval(expanded)
        result.is_a?(Integer) ? result : (result ? 1 : 0)
      rescue StandardError
        0
      end
    end

    def self.run_export(args)
      if args.empty?
        # List all environment variables
        ENV.each { |k, v| puts "#{k}=#{v}" }
      else
        args.each do |arg|
          if arg.include?('=')
            key, value = arg.split('=', 2)
            if readonly?(key)
              puts "export: #{key}: readonly variable"
              next
            end
            if restricted_mode? && RESTRICTED_VARIABLES.include?(key)
              $stderr.puts "rubish: #{key}: readonly variable"
              next
            end
            # Strip quotes from value
            value = strip_quotes(value)
            # Apply attributes if any
            value = apply_attributes(key, value)
            ENV[key] = value
            # Mark as exported
            @var_attributes[key] ||= Set.new
            @var_attributes[key] << :export
          else
            # Just export existing variable (silently, like bash)
            @var_attributes[arg] ||= Set.new
            @var_attributes[arg] << :export
          end
        end
      end
      true
    end

    def self.run_pwd(args)
      # pwd [-L|-P]
      # -L: print logical path (may contain symlinks, default)
      # -P: print physical path (no symlinks)
      physical = set_option?('P')

      args.each do |arg|
        case arg
        when '-P'
          physical = true
        when '-L'
          physical = false
        end
      end

      if physical
        puts File.realpath(Dir.pwd)
      else
        # Use PWD if set and valid, otherwise Dir.pwd
        pwd = ENV['PWD']
        if pwd && File.directory?(pwd)
          puts pwd
        else
          puts Dir.pwd
        end
      end
      true
    end

    # Record timestamp for a history entry
    def self.record_history_timestamp(index, time = Time.now)
      @history_timestamps[index] = time
    end

    # Get timestamp for a history entry
    def self.get_history_timestamp(index)
      @history_timestamps[index]
    end

    # Clear all history timestamps
    def self.clear_history_timestamps
      @history_timestamps.clear
    end

    # Remove timestamp for a specific index and reindex remaining
    def self.remove_history_timestamp(index)
      @history_timestamps.delete(index)
      # Reindex: shift all timestamps after deleted index down by 1
      new_timestamps = {}
      @history_timestamps.each do |idx, time|
        if idx > index
          new_timestamps[idx - 1] = time
        else
          new_timestamps[idx] = time
        end
      end
      @history_timestamps = new_timestamps
    end

    def self.run_history(args)
      # Parse options
      clear = false
      delete_offset = nil
      append_to_file = false
      read_new = false
      read_all = false
      write_all = false
      print_expand = false
      store_args = false

      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-c'
          clear = true
        when '-d'
          i += 1
          delete_offset = args[i]&.to_i
          if delete_offset.nil?
            $stderr.puts 'history: -d: option requires an argument'
            return false
          end
        when '-a'
          append_to_file = true
        when '-n'
          read_new = true
        when '-r'
          read_all = true
        when '-w'
          write_all = true
        when '-p'
          print_expand = true
          i += 1
          break  # Remaining args are for expansion
        when '-s'
          store_args = true
          i += 1
          break  # Remaining args are for storing
        when /^-/
          $stderr.puts "history: #{arg}: invalid option"
          return false
        else
          break  # First non-option is count or filename
        end
        i += 1
      end

      remaining_args = args[i..]

      # Handle -c: clear history
      if clear
        Reline::HISTORY.clear
        clear_history_timestamps
        @last_history_line = 0
        return true
      end

      # Handle -d offset: delete entry
      if delete_offset
        # Convert to 0-based index (history numbers are 1-based)
        index = delete_offset - 1
        if index < 0 || index >= Reline::HISTORY.size
          $stderr.puts "history: #{delete_offset}: history position out of range"
          return false
        end
        Reline::HISTORY.delete_at(index)
        remove_history_timestamp(index)
        return true
      end

      # Handle -a: append new lines to history file
      if append_to_file
        @history_appender&.call
        return true
      end

      # Handle -n: read new lines from history file
      if read_new
        file = @history_file_getter&.call
        return true unless file && File.exist?(file)

        begin
          lines = File.readlines(file, chomp: true)
          # Read lines after what we've already read
          file_last_line = @last_history_line
          new_lines = lines[file_last_line..]
          if new_lines && !new_lines.empty?
            new_lines.each { |line| Reline::HISTORY << line }
            @last_history_line = lines.size
          end
        rescue => e
          $stderr.puts "history: #{e.message}"
          return false
        end
        return true
      end

      # Handle -r: read history file (replace current)
      if read_all
        Reline::HISTORY.clear
        clear_history_timestamps
        @last_history_line = 0
        @history_loader&.call
        return true
      end

      # Handle -w: write history to file
      if write_all
        @history_saver&.call
        return true
      end

      # Handle -p: print history expansion
      if print_expand
        # For now, just print args as-is (full history expansion would require more work)
        puts remaining_args.join(' ')
        return true
      end

      # Handle -s: store args as single history entry
      if store_args
        line = remaining_args.join(' ')
        unless line.empty?
          index = Reline::HISTORY.size
          Reline::HISTORY << line
          record_history_timestamp(index)
        end
        return true
      end

      # Default: display history
      history = Reline::HISTORY.to_a
      count = remaining_args.first&.to_i || history.length

      if count <= 0
        count = history.length
      end

      start_index = [history.length - count, 0].max
      histtimeformat = ENV['HISTTIMEFORMAT']

      history[start_index..].each_with_index do |line, idx|
        history_num = start_index + idx + 1
        if histtimeformat && !histtimeformat.empty?
          timestamp = get_history_timestamp(start_index + idx)
          if timestamp
            formatted_time = timestamp.strftime(histtimeformat)
            puts format('%5d  %s%s', history_num, formatted_time, line)
          else
            # No timestamp recorded, show without time
            puts format('%5d  %s', history_num, line)
          end
        else
          puts format('%5d  %s', history_num, line)
        end
      end
      true
    end

    def self.run_alias(args)
      if args.empty?
        # List all aliases
        @aliases.each { |name, value| puts "alias #{name}='#{value}'" }
      else
        args.each do |arg|
          if arg.include?('=')
            name, value = arg.split('=', 2)
            # Remove surrounding quotes if present
            value = value.sub(/\A(['"])(.*)\1\z/, '\2')
            @aliases[name] = value
          else
            # Show specific alias
            if @aliases.key?(arg)
              puts "alias #{arg}='#{@aliases[arg]}'"
            else
              puts "alias: #{arg}: not found"
            end
          end
        end
      end
      true
    end

    def self.run_unalias(args)
      if args.empty?
        puts 'unalias: usage: unalias name [name ...]'
        return false
      end

      args.each do |name|
        if @aliases.key?(name)
          @aliases.delete(name)
        else
          puts "unalias: #{name}: not found"
        end
      end
      true
    end

    def self.expand_alias(line)
      return line if line.empty?

      # expand_aliases: when disabled, don't expand aliases
      return line unless shopt_enabled?('expand_aliases')

      # Extract the first word
      first_word = line.split(/\s/, 2).first
      return line unless first_word

      if @aliases.key?(first_word)
        rest = line[first_word.length..]
        "#{@aliases[first_word]}#{rest}"
      else
        line
      end
    end

    def self.clear_aliases
      @aliases.clear
    end

    def self.run_source(args)
      if args.empty?
        puts 'source: usage: source filename [arguments]'
        return false
      end

      file = args.first
      original_file = file

      # Restricted mode: cannot source files with '/' in the name
      if restricted_mode? && file.include?('/')
        $stderr.puts "rubish: #{file}: restricted: cannot specify `/' in command names"
        return false
      end

      # If file contains a slash, use it directly (absolute or relative path)
      if file.include?('/')
        file = File.expand_path(file)
      else
        # No slash - check current directory first, then PATH if sourcepath enabled
        if File.exist?(file)
          file = File.expand_path(file)
        elsif shopt_enabled?('sourcepath')
          # Search in PATH
          found = find_file_in_path(file)
          if found
            file = found
          else
            file = File.expand_path(file)  # Will fail below with proper error
          end
        else
          file = File.expand_path(file)
        end
      end

      unless File.exist?(file)
        puts "source: #{original_file}: No such file or directory"
        return false
      end

      unless @executor
        puts 'source: executor not configured'
        return false
      end

      # Save and set script name, positional params, and source file
      old_script_name = @script_name_getter&.call
      old_positional_params = @positional_params_getter&.call
      old_source_file = @source_file_getter&.call
      @script_name_setter&.call(file)
      @positional_params_setter&.call(args[1..] || [])
      # bash_source_fullpath: when enabled, store full path; when disabled, use filename as specified
      source_file_value = shopt_enabled?('bash_source_fullpath') ? file : original_file
      @source_file_setter&.call(source_file_value)

      # Disable history expansion while sourcing (bash behavior)
      old_sourcing = @sourcing_file
      @sourcing_file = true

      return_code = catch(:return) do
        buffer = +''
        depth = 0
        pending_function_def = false  # Track if we're waiting for { after ()
        lines = File.readlines(file, chomp: true)
        i = 0

        while i < lines.length
          line = lines[i].strip
          i += 1
          next if line.empty? || line.start_with?('#')

          # Check for heredoc in this line
          heredoc_info = detect_heredoc(line)
          if heredoc_info
            delimiter, strip_tabs = heredoc_info
            heredoc_lines = []
            # Collect heredoc content from subsequent lines
            while i < lines.length
              heredoc_line = lines[i]
              i += 1
              # Check for delimiter (possibly with leading tabs if strip_tabs)
              check_line = strip_tabs ? heredoc_line.sub(/\A\t+/, '') : heredoc_line
              if check_line.strip == delimiter
                break
              end
              heredoc_lines << heredoc_line
            end
            # Set heredoc content before executing
            content = heredoc_lines.join("\n") + (heredoc_lines.empty? ? '' : "\n")
            @heredoc_content_setter&.call(content)
          end

          # Remember if we're waiting for function body BEFORE processing this line
          was_pending_function = pending_function_def

          # Track control structure depth
          words = line.split(/\s+/)
          words.each do |word|
            case word
            when 'if', 'unless', 'while', 'until', 'for', 'case', 'def'
              depth += 1
            when 'fi', 'done', 'esac', 'end'
              depth -= 1
            when '{'
              # If pending function def, don't double-count the depth
              if pending_function_def
                pending_function_def = false
              else
                depth += 1
              end
            when '}'
              depth -= 1
            end
          end

          # Track subshell depth separately (only standalone ( at start of word)
          # This handles: ( cmd ) but not: arr=( ... ) or $( ... )
          if line =~ /\A\s*\(/
            depth += 1
          end
          # Check if line is just ) or ends with ) not preceded by ( on same line
          if line =~ /\A\s*\)\s*\z/
            depth -= 1
          end

          # Detect function definition: line ends with () or "function name"
          # These need { on next line, so set flag and increment depth
          if line =~ /\(\)\s*$/ || (line =~ /\Afunction\s+\w+\s*$/)
            pending_function_def = true
            depth += 1
          end

          # Accumulate lines - use newline for function definitions, semicolon otherwise
          if buffer.empty?
            buffer = line
          elsif was_pending_function
            # Function definitions need newline between () and {
            buffer = "#{buffer}\n#{line}"
          else
            # Other statements can be joined with semicolon
            buffer = "#{buffer}; #{line}"
          end

          # Execute when we have a complete statement
          if depth == 0 && !pending_function_def
            begin
              @executor.call(buffer)
            rescue SyntaxError => e
              puts "source: #{e.message}"
            end
            buffer = +''
          end
        end

        # Execute any remaining buffer (incomplete statement)
        unless buffer.empty?
          begin
            @executor.call(buffer)
          rescue SyntaxError => e
            puts "source: #{e.message}"
          end
        end

        nil
      end

      # Restore script name, positional params, source file, and sourcing flag
      @script_name_setter&.call(old_script_name) if old_script_name
      @positional_params_setter&.call(old_positional_params) if old_positional_params
      @source_file_setter&.call(old_source_file) if old_source_file
      @sourcing_file = old_sourcing

      return_code.nil? || return_code == 0
    end

    def self.run_shift(args)
      n = args.first&.to_i || 1

      return false if n < 0

      params = @positional_params_getter&.call || []

      if n > params.length
        # shift_verbose: print error if shift count exceeds positional parameters
        if shopt_enabled?('shift_verbose')
          $stderr.puts format_error('shift count out of range', command: 'shift')
        end
        return false
      end

      @positional_params_setter&.call(params.drop(n))
      true
    end

    # Shell option flags (set -o options)
    @set_options = {
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

    def self.set_options
      @set_options
    end

    def self.set_option?(flag)
      @set_options[flag] || false
    end

    # Check if shell is in restricted mode
    def self.restricted_mode?
      @set_options['r'] || @shell_options['restricted_shell']
    end

    # Enable restricted mode (cannot be disabled once set)
    def self.enable_restricted_mode
      @set_options['r'] = true
      @shell_options['restricted_shell'] = true
    end

    # Check if shell is interactive
    def self.interactive_mode?
      @set_options['i']
    end

    # Enable interactive mode (read-only, set at startup)
    # Also enables monitor mode (job control) as per bash behavior
    def self.enable_interactive_mode
      @set_options['i'] = true
      @set_options['m'] = true  # Job control enabled for interactive shells
    end

    # List of variables that cannot be modified in restricted mode
    RESTRICTED_VARIABLES = %w[SHELL ENV PATH BASH_ENV SHELLOPTS RUBISHOPTS].freeze

    def self.run_set(args)
      # set [-+abCefhmnuvx] [-o option] [--] [arg...]
      # With no args, clear positional params (original behavior)
      if args.empty?
        @positional_params_setter&.call([])
        return true
      end

      i = 0
      while i < args.length
        arg = args[i]

        if arg == '--'
          # Everything after -- is positional params
          @positional_params_setter&.call(args[i + 1..] || [])
          return true
        elsif arg == '-o'
          # Long option form: set -o errexit, or just set -o to list
          i += 1
          opt_name = args[i]
          if opt_name
            set_long_option(opt_name, true)
          else
            # set -o with no option name lists all options
            list_set_options
            return true
          end
        elsif arg == '+o'
          # Disable long option: set +o errexit, or list with set +o
          i += 1
          opt_name = args[i]
          if opt_name
            set_long_option(opt_name, false)
          else
            list_set_options
            return true
          end
        elsif arg.start_with?('-') && arg.length > 1 && arg != '-'
          # Short options: -e, -x, -ex
          arg[1..].each_char do |c|
            if @set_options.key?(c)
              if c == 'r'
                # Enable restricted mode (syncs with restricted_shell shopt)
                enable_restricted_mode
              elsif c == 'i'
                # Cannot enable interactive mode via set (read-only)
                $stderr.puts 'rubish: set: interactive: cannot modify at runtime'
                return false
              else
                @set_options[c] = true
              end
            end
          end
        elsif arg.start_with?('+') && arg.length > 1
          # Disable short options: +e, +x
          arg[1..].each_char do |c|
            if @set_options.key?(c)
              if c == 'r' && restricted_mode?
                # Cannot disable restricted mode once enabled
                $stderr.puts 'rubish: set: restricted: cannot modify in restricted mode'
                return false
              elsif c == 'i'
                # Cannot disable interactive mode (read-only)
                $stderr.puts 'rubish: set: interactive: cannot modify at runtime'
                return false
              else
                @set_options[c] = false
              end
            end
          end
        else
          # Positional parameters
          @positional_params_setter&.call(args[i..])
          return true
        end
        i += 1
      end
      true
    end

    def self.list_set_options
      # Print current option settings
      long_names = {
        'B' => 'braceexpand', 'H' => 'histexpand',
        'e' => 'errexit', 'E' => 'errtrace', 'T' => 'functrace',
        'x' => 'xtrace', 'u' => 'nounset', 'n' => 'noexec', 'v' => 'verbose',
        'f' => 'noglob', 'C' => 'noclobber', 'a' => 'allexport', 'b' => 'notify',
        'h' => 'hashall', 'm' => 'monitor', 'pipefail' => 'pipefail',
        'globstar' => 'globstar', 'nullglob' => 'nullglob', 'failglob' => 'failglob',
        'dotglob' => 'dotglob', 'nocaseglob' => 'nocaseglob', 'ignoreeof' => 'ignoreeof',
        'extglob' => 'extglob', 'P' => 'physical', 'emacs' => 'emacs', 'vi' => 'vi',
        'nocasematch' => 'nocasematch', 't' => 'onecmd', 'k' => 'keyword',
        'p' => 'privileged', 'history' => 'history', 'nolog' => 'nolog',
        'r' => 'restricted'
      }
      @set_options.each do |flag, value|
        name = long_names[flag] || flag
        state = value ? '-o' : '+o'
        puts "set #{state} #{name}"
      end
      true
    end

    # SHELLOPTS: colon-separated list of enabled set -o options
    def self.shellopts
      long_names = {
        'B' => 'braceexpand', 'H' => 'histexpand',
        'e' => 'errexit', 'E' => 'errtrace', 'T' => 'functrace',
        'x' => 'xtrace', 'u' => 'nounset', 'n' => 'noexec', 'v' => 'verbose',
        'f' => 'noglob', 'C' => 'noclobber', 'a' => 'allexport', 'b' => 'notify',
        'h' => 'hashall', 'm' => 'monitor', 'pipefail' => 'pipefail',
        'globstar' => 'globstar', 'nullglob' => 'nullglob', 'failglob' => 'failglob',
        'dotglob' => 'dotglob', 'nocaseglob' => 'nocaseglob', 'ignoreeof' => 'ignoreeof',
        'extglob' => 'extglob', 'P' => 'physical', 'emacs' => 'emacs', 'vi' => 'vi',
        'nocasematch' => 'nocasematch', 't' => 'onecmd', 'k' => 'keyword',
        'p' => 'privileged', 'history' => 'history', 'nolog' => 'nolog',
        'r' => 'restricted'
      }
      enabled = @set_options.select { |_, v| v }.keys.map { |k| long_names[k] || k }
      enabled.sort.join(':')
    end

    # RUBISHOPTS: colon-separated list of enabled shopt options (equivalent to BASHOPTS)
    def self.rubishopts
      enabled = []
      SHELL_OPTIONS.each_key do |name|
        if @shell_options.key?(name)
          enabled << name if @shell_options[name]
        elsif SHELL_OPTIONS[name][0]  # default value is true
          enabled << name
        end
      end
      enabled.sort.join(':')
    end

    # BASHOPTS: colon-separated list of enabled shopt options (read-only)
    # This is the bash-standard name; RUBISHOPTS is the rubish-specific equivalent
    def self.bashopts
      rubishopts
    end

    def self.set_long_option(name, value)
      mapping = {
        'braceexpand' => 'B', 'histexpand' => 'H',
        'errexit' => 'e', 'errtrace' => 'E', 'functrace' => 'T',
        'xtrace' => 'x', 'nounset' => 'u', 'noexec' => 'n', 'verbose' => 'v',
        'noglob' => 'f', 'noclobber' => 'C', 'allexport' => 'a', 'notify' => 'b',
        'hashall' => 'h', 'monitor' => 'm', 'pipefail' => 'pipefail',
        'globstar' => 'globstar', 'nullglob' => 'nullglob', 'failglob' => 'failglob',
        'dotglob' => 'dotglob', 'nocaseglob' => 'nocaseglob', 'ignoreeof' => 'ignoreeof',
        'extglob' => 'extglob', 'physical' => 'P', 'emacs' => 'emacs', 'vi' => 'vi',
        'nocasematch' => 'nocasematch', 'onecmd' => 't', 'keyword' => 'k',
        'privileged' => 'p', 'history' => 'history', 'nolog' => 'nolog',
        'restricted' => 'r'
      }
      flag = mapping[name]
      return unless flag

      # Handle restricted mode specially
      if name == 'restricted'
        if value
          enable_restricted_mode
        elsif restricted_mode?
          $stderr.puts 'rubish: set: restricted: cannot modify in restricted mode'
          return false
        end
        return true
      end

      # vi and emacs are mutually exclusive
      if flag == 'vi' && value
        @set_options['vi'] = true
        @set_options['emacs'] = false
        Reline.vi_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && value
        @set_options['emacs'] = true
        @set_options['vi'] = false
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'vi' && !value
        # Disabling vi enables emacs
        @set_options['vi'] = false
        @set_options['emacs'] = true
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && !value
        # Disabling emacs enables vi
        @set_options['emacs'] = false
        @set_options['vi'] = true
        Reline.vi_editing_mode if defined?(Reline)
      else
        @set_options[flag] = value
      end
    end

    def self.run_return(args)
      code = args.first&.to_i || 0
      throw :return, code
    end

    def self.run_break(args)
      # Optional: break N to break out of N levels (default 1)
      levels = args.first&.to_i || 1
      throw :break_loop, levels
    end

    def self.run_continue(args)
      # Optional: continue N to continue Nth enclosing loop (default 1)
      levels = args.first&.to_i || 1
      throw :continue_loop, levels
    end

    def self.run_test(args)
      # Remove trailing ] if called as [
      args = args[0...-1] if args.last == ']'

      return false if args.empty?

      # Handle compound expressions with -a (AND) and -o (OR)
      # -o has lower precedence than -a
      if args.include?('-o')
        idx = args.index('-o')
        left_result = run_test(args[0...idx])
        right_result = run_test(args[(idx + 1)..])
        return left_result || right_result
      end

      if args.include?('-a')
        idx = args.index('-a')
        left_result = run_test(args[0...idx])
        right_result = run_test(args[(idx + 1)..])
        return left_result && right_result
      end

      # Negation
      if args.first == '!'
        return !run_test(args[1..])
      end

      # Single argument - true if non-empty
      return !args.first.empty? if args.length == 1

      # Unary operators
      if args.length == 2
        op, arg = args
        case op
        # String tests
        when '-z' then return arg.empty?
        when '-n' then return !arg.empty?
        # Variable tests
        when '-v' then return ENV.key?(arg) || nameref?(arg)
        when '-R' then return nameref?(arg)
        # File existence and type tests
        when '-e' then return File.exist?(arg)
        when '-f' then return File.file?(arg)
        when '-d' then return File.directory?(arg)
        when '-b' then return File.exist?(arg) && File.stat(arg).blockdev?
        when '-c' then return File.exist?(arg) && File.stat(arg).chardev?
        when '-L', '-h' then return File.symlink?(arg)
        when '-S' then return File.exist?(arg) && File.stat(arg).socket?
        when '-p' then return File.exist?(arg) && File.stat(arg).pipe?
        when '-t'
          # -t fd: true if file descriptor is open and refers to a terminal
          fd = arg.to_i
          begin
            io = case fd
                 when 0 then $stdin
                 when 1 then $stdout
                 when 2 then $stderr
                 else IO.new(fd) rescue nil
                 end
            return io&.tty? || false
          rescue
            return false
          end
        # File permission tests
        when '-r' then return File.readable?(arg)
        when '-w' then return File.writable?(arg)
        when '-x' then return File.executable?(arg)
        when '-s' then return File.exist?(arg) && File.size(arg) > 0
        when '-u'
          # setuid bit
          return File.exist?(arg) && (File.stat(arg).mode & 0o4000) != 0
        when '-g'
          # setgid bit
          return File.exist?(arg) && (File.stat(arg).mode & 0o2000) != 0
        when '-k'
          # sticky bit
          return File.exist?(arg) && (File.stat(arg).mode & 0o1000) != 0
        when '-O'
          # owned by effective user ID
          return File.exist?(arg) && File.stat(arg).uid == Process.euid
        when '-G'
          # owned by effective group ID
          return File.exist?(arg) && File.stat(arg).gid == Process.egid
        when '-N'
          # modified since last read
          return File.exist?(arg) && File.mtime(arg) > File.atime(arg)
        end
      end

      # Binary operators
      if args.length == 3
        left, op, right = args
        case op
        # String comparisons
        when '=' then return left == right
        when '==' then return left == right
        when '!=' then return left != right
        when '<' then return left < right
        when '>' then return left > right
        # Integer comparisons
        when '-eq' then return left.to_i == right.to_i
        when '-ne' then return left.to_i != right.to_i
        when '-lt' then return left.to_i < right.to_i
        when '-le' then return left.to_i <= right.to_i
        when '-gt' then return left.to_i > right.to_i
        when '-ge' then return left.to_i >= right.to_i
        # File comparisons
        when '-nt'
          # file1 is newer than file2
          return false unless File.exist?(left) && File.exist?(right)
          return File.mtime(left) > File.mtime(right)
        when '-ot'
          # file1 is older than file2
          return false unless File.exist?(left) && File.exist?(right)
          return File.mtime(left) < File.mtime(right)
        when '-ef'
          # file1 and file2 refer to same device and inode
          return false unless File.exist?(left) && File.exist?(right)
          stat1 = File.stat(left)
          stat2 = File.stat(right)
          return stat1.dev == stat2.dev && stat1.ino == stat2.ino
        end
      end

      false
    end

    def self.run_echo(args)
      newline = true
      # xpg_echo: expand backslash escapes by default when enabled
      interpret_escapes = shopt_enabled?('xpg_echo')
      start_idx = 0

      # Parse options: -n (no newline), -e (enable escapes), -E (disable escapes)
      # Options can be combined like -ne, -en, -neE, etc.
      while start_idx < args.length && args[start_idx]&.start_with?('-') && args[start_idx] != '-'
        opt = args[start_idx]
        # Check if it's a valid option string (only contains n, e, E after -)
        break unless opt[1..].chars.all? { |c| 'neE'.include?(c) }

        opt[1..].each_char do |c|
          case c
          when 'n' then newline = false
          when 'e' then interpret_escapes = true
          when 'E' then interpret_escapes = false
          end
        end
        start_idx += 1
      end

      output = args[start_idx..].join(' ')

      # Process escape sequences if enabled
      if interpret_escapes
        output = process_echo_escapes(output)
        # Check for \c which stops output
        if output.include?("\x00STOP_OUTPUT\x00")
          output = output.split("\x00STOP_OUTPUT\x00").first || ''
          newline = false
        end
      end

      if newline
        puts output
      else
        print output
      end

      true
    end

    # Process escape sequences for echo (slightly different from printf)
    def self.process_echo_escapes(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\' && i + 1 < str.length
          case str[i + 1]
          when 'n' then result << "\n"; i += 2
          when 't' then result << "\t"; i += 2
          when 'r' then result << "\r"; i += 2
          when 'a' then result << "\a"; i += 2
          when 'b' then result << "\b"; i += 2
          when 'f' then result << "\f"; i += 2
          when 'v' then result << "\v"; i += 2
          when '\\' then result << '\\'; i += 2
          when 'e', 'E' then result << "\e"; i += 2  # escape character
          when 'c'
            # \c stops output (no further characters printed, no newline)
            result << "\x00STOP_OUTPUT\x00"
            break
          when '0'
            # Octal escape \0nnn (up to 3 octal digits)
            i += 2
            octal = +''
            while octal.length < 3 && i < str.length && str[i] >= '0' && str[i] <= '7'
              octal << str[i]
              i += 1
            end
            result << (octal.empty? ? "\0" : octal.to_i(8).chr)
          when 'x'
            # Hex escape \xHH (1 or 2 hex digits)
            i += 2
            hex = +''
            while hex.length < 2 && i < str.length && str[i] =~ /[0-9a-fA-F]/
              hex << str[i]
              i += 1
            end
            result << (hex.empty? ? '\\x' : hex.to_i(16).chr)
          else
            # Unknown escape, keep as-is
            result << str[i]
            i += 1
          end
        else
          result << str[i]
          i += 1
        end
      end
      result
    end

    def self.run_printf(args)
      # printf [-v var] format [arguments...]
      # Supports: %s, %d, %i, %f, %e, %g, %x, %X, %o, %c, %b, %q, %%
      # Also supports width, precision, and flags: %-10s, %05d, %.2f, etc.
      # Dynamic width/precision: %*s (width from arg), %.*s (precision from arg), %*.*s (both)
      # %(fmt)T: format time using strftime format (arg is epoch seconds, -1=now, -2=shell start)
      # -v var: assign output to shell variable var instead of printing

      var_name = nil

      # Parse -v option
      while args.first&.start_with?('-')
        break if args.first == '--'
        if args.first == '-v'
          args.shift
          var_name = args.shift
          unless var_name
            $stderr.puts 'printf: -v: option requires an argument'
            return false
          end
          # Validate variable name
          unless var_name =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
            $stderr.puts "printf: `#{var_name}': not a valid identifier"
            return false
          end
        else
          $stderr.puts "printf: #{args.first}: invalid option"
          return false
        end
      end

      # Consume -- if present
      args.shift if args.first == '--'

      if args.empty?
        $stderr.puts 'printf: usage: printf [-v var] format [arguments]'
        return false
      end

      format = args.first
      arguments = args[1..] || []
      arg_index = 0

      # Process escape sequences in format string
      format = process_escape_sequences(format)

      # Build output by processing format specifiers
      output = +''
      i = 0
      while i < format.length
        if format[i] == '%'
          if i + 1 < format.length && format[i + 1] == '%'
            # Literal %
            output << '%'
            i += 2
            next
          end

          # Parse format specifier
          spec_start = i
          i += 1

          # Check for %(strftime_format)T time format
          if i < format.length && format[i] == '('
            # Find the closing )T
            paren_start = i + 1
            paren_end = format.index(')T', i)
            if paren_end
              strftime_fmt = format[paren_start...paren_end]
              i = paren_end + 2  # Skip past )T

              # Get the time argument
              arg = if arg_index < arguments.length
                      arguments[arg_index]
                    else
                      '-1'  # Default to current time
                    end
              arg_index += 1

              # Convert argument to time
              time = case arg.to_s
                     when '-1', ''
                       Time.now
                     when '-2'
                       # Shell start time - use a class variable or fall back to current
                       @shell_start_time ||= Time.now
                     else
                       Time.at(arg.to_i)
                     end

              output << time.strftime(strftime_fmt)
              next
            end
          end

          # Parse flags
          flags = +''
          while i < format.length && '-+ #0'.include?(format[i])
            flags << format[i]
            i += 1
          end

          # Parse width (can be * for dynamic width from argument)
          width = +''
          if i < format.length && format[i] == '*'
            # Dynamic width from argument
            i += 1
            width_arg = if arg_index < arguments.length
                          arguments[arg_index]
                        else
                          '0'
                        end
            arg_index += 1
            width_val = width_arg.to_i
            # Negative width means left-align
            if width_val < 0
              flags << '-' unless flags.include?('-')
              width_val = width_val.abs
            end
            width = width_val.to_s
          else
            while i < format.length && format[i] =~ /\d/
              width << format[i]
              i += 1
            end
          end

          # Parse precision (can be * for dynamic precision from argument)
          precision = nil
          if i < format.length && format[i] == '.'
            i += 1
            if i < format.length && format[i] == '*'
              # Dynamic precision from argument
              i += 1
              prec_arg = if arg_index < arguments.length
                           arguments[arg_index]
                         else
                           '0'
                         end
              arg_index += 1
              prec_val = prec_arg.to_i
              # Negative precision is treated as if precision were omitted
              precision = prec_val >= 0 ? prec_val.to_s : nil
            else
              precision = +''
              while i < format.length && format[i] =~ /\d/
                precision << format[i]
                i += 1
              end
            end
          end

          # Parse conversion specifier
          if i < format.length
            specifier = format[i]
            i += 1

            # Get argument (reuse arguments if we run out)
            arg = if arg_index < arguments.length
                    arguments[arg_index]
                  else
                    specifier =~ /[diouxXeEfFgG]/ ? '0' : ''
                  end
            arg_index += 1

            # Format the argument
            output << format_arg(specifier, arg, flags, width, precision)
          end
        else
          output << format[i]
          i += 1
        end
      end

      if var_name
        # Assign to variable instead of printing
        ENV[var_name] = output
      else
        print output
      end
      true
    end

    def self.process_escape_sequences(str)
      result = +''
      i = 0
      while i < str.length
        if str[i] == '\\' && i + 1 < str.length
          next_char = str[i + 1]
          case next_char
          when 'n' then result << "\n"; i += 2
          when 't' then result << "\t"; i += 2
          when 'r' then result << "\r"; i += 2
          when 'a' then result << "\a"; i += 2
          when 'b' then result << "\b"; i += 2
          when 'f' then result << "\f"; i += 2
          when 'v' then result << "\v"; i += 2
          when 'e', 'E' then result << "\e"; i += 2
          when '\\' then result << '\\'; i += 2
          when "'" then result << "'"; i += 2
          when '"' then result << '"'; i += 2
          when '?'  then result << '?'; i += 2
          when 'x'
            # Hex escape \xNN
            hex = str[i + 2, 2]
            if hex =~ /\A[0-9a-fA-F]{1,2}\z/
              result << hex.to_i(16).chr
              i += 2 + hex.length
            else
              result << str[i]; i += 1
            end
          when 'u'
            # Unicode escape \uNNNN (4 hex digits)
            hex = str[i + 2, 4]
            if hex =~ /\A[0-9a-fA-F]{4}\z/
              result << [hex.to_i(16)].pack('U')
              i += 6
            else
              result << str[i]; i += 1
            end
          when 'U'
            # Unicode escape \UNNNNNNNN (8 hex digits)
            hex = str[i + 2, 8]
            if hex =~ /\A[0-9a-fA-F]{8}\z/
              result << [hex.to_i(16)].pack('U')
              i += 10
            else
              result << str[i]; i += 1
            end
          when 'c'
            # Control character \cX
            if i + 2 < str.length
              ctrl_char = str[i + 2]
              result << (ctrl_char.ord & 0x1f).chr
              i += 3
            else
              result << str[i]; i += 1
            end
          when /[0-7]/
            # Octal escape \NNN (1-3 digits)
            octal = str[i + 1, 3].match(/\A[0-7]{1,3}/)[0]
            result << octal.to_i(8).chr
            i += 1 + octal.length
          else
            # Unknown escape - keep backslash and character
            result << str[i, 2]; i += 2
          end
        else
          result << str[i]; i += 1
        end
      end
      result
    end

    def self.shell_quote(str)
      # Quote a string for safe reuse as shell input (like bash's printf %q)
      # Returns a string that, when parsed by the shell, yields the original string

      # Empty string needs explicit quoting
      return "''" if str.empty?

      # If string contains only safe characters, no quoting needed
      # Safe chars: alphanumeric, underscore, hyphen, dot, slash, colon, at, percent, plus, comma, equals
      if str.match?(/\A[a-zA-Z0-9_\-.\/:@%+=,]+\z/)
        return str
      end

      # Use $'...' syntax for strings with control characters
      if str.match?(/[\x00-\x1f\x7f]/)
        return "$'" + str.gsub(/[\x00-\x1f\x7f'\\]/) { |c|
          case c
          when "\n" then '\\n'
          when "\t" then '\\t'
          when "\r" then '\\r'
          when "\a" then '\\a'
          when "\b" then '\\b'
          when "\f" then '\\f'
          when "\v" then '\\v'
          when "\e" then '\\e'
          when "'" then "\\'"
          when '\\' then '\\\\'
          else
            # Other control characters as octal
            format('\\%03o', c.ord)
          end
        } + "'"
      end

      # For strings with single quotes, use $'...' syntax
      if str.include?("'")
        return "$'" + str.gsub(/['\\]/) { |c|
          c == "'" ? "\\'" : '\\\\'
        } + "'"
      end

      # For other special characters, use single quotes
      # (single quotes preserve everything literally except single quote itself)
      "'" + str + "'"
    end

    def self.format_arg(specifier, arg, flags, width, precision)
      width_int = width.empty? ? nil : width.to_i
      prec_int = precision.nil? ? nil : (precision.empty? ? 0 : precision.to_i)

      result = case specifier
               when 's'
                 # String
                 s = arg.to_s
                 s = s[0, prec_int] if prec_int
                 s
               when 'd', 'i'
                 # Signed integer
                 num = arg.to_i
                 if prec_int
                   format("%0#{prec_int}d", num)
                 else
                   num.to_s
                 end
               when 'u'
                 # Unsigned integer
                 num = arg.to_i
                 num = num & 0xFFFFFFFF if num < 0
                 num.to_s
               when 'o'
                 # Octal
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0' : ''
                 "#{prefix}#{num.to_s(8)}"
               when 'x'
                 # Hexadecimal lowercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0x' : ''
                 "#{prefix}#{num.to_s(16)}"
               when 'X'
                 # Hexadecimal uppercase
                 num = arg.to_i
                 prefix = flags.include?('#') ? '0X' : ''
                 "#{prefix}#{num.to_s(16).upcase}"
               when 'f', 'F'
                 # Floating point
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}f", num)
               when 'e'
                 # Scientific notation lowercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}e", num)
               when 'E'
                 # Scientific notation uppercase
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}E", num)
               when 'g'
                 # Shorter of %e or %f
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}g", num)
               when 'G'
                 # Shorter of %E or %F
                 num = arg.to_f
                 prec = prec_int || 6
                 format("%.#{prec}G", num)
               when 'c'
                 # Character
                 arg.to_s[0] || ''
               when 'b'
                 # String with backslash escapes
                 process_escape_sequences(arg.to_s)
               when 'q'
                 # Shell-quoted string (safe for reuse as shell input)
                 shell_quote(arg.to_s)
               else
                 arg.to_s
               end

      # Apply width and alignment
      if width_int
        if flags.include?('-')
          # Left-justify
          result = result.ljust(width_int)
        elsif flags.include?('0') && specifier =~ /[diouxXeEfFgG]/
          # Zero-pad numbers
          if result[0] == '-'
            result = "-#{result[1..].rjust(width_int - 1, '0')}"
          else
            result = result.rjust(width_int, '0')
          end
        else
          # Right-justify with spaces
          result = result.rjust(width_int)
        end
      end

      # Handle + flag for numbers
      if flags.include?('+') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = "+#{result}"
      elsif flags.include?(' ') && specifier =~ /[dieEfFgG]/ && !result.start_with?('-')
        result = " #{result}"
      end

      result
    end

    def self.run_type(args)
      # type [-afptP] name [name ...]
      # -a: display all locations containing an executable named name
      # -f: suppress function lookup
      # -p: return path only for external commands
      # -t: output single word: alias, keyword, function, builtin, file, or nothing
      # -P: force PATH search even if name is alias, function, or builtin

      if args.empty?
        puts 'type: usage: type [-afptP] name [name ...]'
        return false
      end

      # Parse options
      show_all = false
      suppress_functions = false
      path_only = false
      type_only = false
      force_path = false
      names = []

      args.each do |arg|
        if arg.start_with?('-') && arg.length > 1
          arg[1..].each_char do |c|
            case c
            when 'a' then show_all = true
            when 'f' then suppress_functions = true
            when 'p' then path_only = true
            when 't' then type_only = true
            when 'P' then force_path = true
            end
          end
        else
          names << arg
        end
      end

      if names.empty?
        puts 'type: usage: type [-afptP] name [name ...]'
        return false
      end

      all_found = true

      names.each do |name|
        found = false

        # Check alias (unless force_path)
        unless force_path
          if @aliases.key?(name)
            found = true
            if type_only
              puts 'alias'
            elsif !path_only
              puts "#{name} is aliased to '#{@aliases[name]}'"
            end
            next unless show_all
          end
        end

        # Check function (unless force_path or suppress_functions)
        unless force_path || suppress_functions
          if @function_checker&.call(name)
            found = true
            if type_only
              puts 'function'
            elsif !path_only
              puts "#{name} is a function"
            end
            next unless show_all
          end
        end

        # Check builtin (unless force_path)
        unless force_path
          if builtin?(name)
            found = true
            if type_only
              puts 'builtin'
            elsif !path_only
              puts "#{name} is a shell builtin"
            end
            next unless show_all
          end
        end

        # Check PATH for external command
        path = find_in_path(name)
        if path
          found = true
          if type_only
            puts 'file'
          elsif path_only || force_path
            puts path
          else
            puts "#{name} is #{path}"
          end
        end

        unless found
          puts "type: #{name}: not found" unless type_only
          all_found = false
        end
      end

      all_found
    end

    # Check if a path matches any EXECIGNORE pattern
    # EXECIGNORE is a colon-separated list of glob patterns
    def self.execignore?(path)
      execignore = ENV['EXECIGNORE']
      return false if execignore.nil? || execignore.empty?

      patterns = execignore.split(':')
      patterns.any? do |pattern|
        next false if pattern.empty?
        File.fnmatch?(pattern, path, File::FNM_PATHNAME) ||
          File.fnmatch?(pattern, File.basename(path), File::FNM_PATHNAME)
      end
    end

    def self.find_in_path(name)
      # If name contains a slash, check if it's executable
      if name.include?('/')
        return nil if execignore?(name)
        return name if File.executable?(name)
        return nil
      end

      # Search PATH
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        next if execignore?(full_path)
        return full_path if File.executable?(full_path) && !File.directory?(full_path)
      end

      nil
    end

    # Find a file in PATH (for source builtin with sourcepath)
    # Unlike find_in_path, this doesn't require the file to be executable
    def self.find_file_in_path(name)
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        return full_path if File.file?(full_path) && File.readable?(full_path)
      end
      nil
    end

    def self.find_all_in_path(name)
      # Find all matching executables in PATH
      results = []

      # If name contains a slash, just check if it's executable
      if name.include?('/')
        results << name if File.executable?(name) && !execignore?(name)
        return results
      end

      # Search PATH
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        next if execignore?(full_path)
        if File.executable?(full_path) && !File.directory?(full_path)
          results << full_path
        end
      end

      results
    end

    def self.run_disown(args)
      # disown [-h] [-ar] [jobspec ...]
      # -h: mark jobs so SIGHUP is not sent (but keep in table)
      # -a: remove all jobs
      # -r: remove only running jobs
      # Without args: removes current job

      mark_nohup = false
      all_jobs = false
      running_only = false
      job_specs = []

      args.each do |arg|
        if arg.start_with?('-') && job_specs.empty?
          arg[1..].each_char do |c|
            case c
            when 'h' then mark_nohup = true
            when 'a' then all_jobs = true
            when 'r' then running_only = true
            else
              puts "disown: -#{c}: invalid option"
              return false
            end
          end
        else
          job_specs << arg
        end
      end

      manager = JobManager.instance

      if all_jobs
        # Remove/mark all jobs
        jobs = manager.all
        jobs = jobs.select(&:running?) if running_only
        jobs.each do |job|
          if mark_nohup
            job.status = :nohup
          else
            manager.remove(job.id)
          end
        end
        return true
      end

      if job_specs.empty?
        # Remove current job
        job = manager.last
        unless job
          puts 'disown: current: no such job'
          return false
        end
        if mark_nohup
          job.status = :nohup
        else
          manager.remove(job.id)
        end
        return true
      end

      # Remove specified jobs
      all_found = true
      job_specs.each do |spec|
        job = nil

        if spec.start_with?('%')
          job_id = spec[1..].to_i
          job = manager.get(job_id)
        else
          # Try as PID
          pid = spec.to_i
          job = manager.find_by_pid(pid)
        end

        unless job
          puts "disown: #{spec}: no such job"
          all_found = false
          next
        end

        if running_only && !job.running?
          next
        end

        if mark_nohup
          job.status = :nohup
        else
          manager.remove(job.id)
        end
      end

      all_found
    end

    def self.run_ulimit(args)
      # ulimit [-HSabcdefiklmnpqrstuvxPRT] [limit]
      # -H: use hard limit
      # -S: use soft limit (default for display)
      # -a: show all limits
      # Resource flags:
      # -c: core file size (blocks)
      # -d: data segment size (kbytes)
      # -e: scheduling priority (nice)
      # -f: file size (blocks) - default
      # -i: pending signals
      # -l: locked memory (kbytes)
      # -m: resident set size (kbytes)
      # -n: open files
      # -p: pipe size (512 bytes)
      # -q: POSIX message queues (bytes)
      # -r: real-time priority
      # -s: stack size (kbytes)
      # -t: CPU time (seconds)
      # -u: user processes
      # -v: virtual memory (kbytes)
      # -x: file locks

      # Resource mapping to Ruby Process constants
      resource_map = {
        'c' => [:RLIMIT_CORE, 512, 'core file size'],           # blocks
        'd' => [:RLIMIT_DATA, 1024, 'data seg size'],           # kbytes
        'f' => [:RLIMIT_FSIZE, 512, 'file size'],               # blocks
        'l' => [:RLIMIT_MEMLOCK, 1024, 'max locked memory'],    # kbytes
        'm' => [:RLIMIT_RSS, 1024, 'max memory size'],          # kbytes
        'n' => [:RLIMIT_NOFILE, 1, 'open files'],               # count
        's' => [:RLIMIT_STACK, 1024, 'stack size'],             # kbytes
        't' => [:RLIMIT_CPU, 1, 'cpu time'],                    # seconds
        'u' => [:RLIMIT_NPROC, 1, 'max user processes'],        # count
        'v' => [:RLIMIT_AS, 1024, 'virtual memory']             # kbytes
      }

      # Add platform-specific resources if available
      resource_map['i'] = [:RLIMIT_SIGPENDING, 1, 'pending signals'] if Process.const_defined?(:RLIMIT_SIGPENDING)
      resource_map['q'] = [:RLIMIT_MSGQUEUE, 1, 'POSIX message queues'] if Process.const_defined?(:RLIMIT_MSGQUEUE)
      resource_map['e'] = [:RLIMIT_NICE, 1, 'scheduling priority'] if Process.const_defined?(:RLIMIT_NICE)
      resource_map['r'] = [:RLIMIT_RTPRIO, 1, 'real-time priority'] if Process.const_defined?(:RLIMIT_RTPRIO)
      resource_map['x'] = [:RLIMIT_LOCKS, 1, 'file locks'] if Process.const_defined?(:RLIMIT_LOCKS)

      use_hard = false
      use_soft = true  # default
      show_all = false
      resource_flag = 'f'  # default is file size
      limit_value = nil

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && limit_value.nil?
          arg[1..].each_char do |c|
            case c
            when 'H'
              use_hard = true
              use_soft = false
            when 'S'
              use_soft = true
              use_hard = false
            when 'a'
              show_all = true
            when *resource_map.keys
              resource_flag = c
            else
              puts "ulimit: -#{c}: invalid option"
              return false
            end
          end
        else
          limit_value = arg
        end
        i += 1
      end

      # Show all limits
      if show_all
        resource_map.each do |flag, (const_sym, divisor, description)|
          next unless Process.const_defined?(const_sym)

          const = Process.const_get(const_sym)
          begin
            soft, hard = Process.getrlimit(const)
            value = use_hard ? hard : soft
            if value == Process::RLIM_INFINITY
              formatted = 'unlimited'
            else
              formatted = (value / divisor).to_s
            end
            unit = case flag
                   when 't' then '(seconds, -t)'
                   when 'n', 'u' then "(-#{flag})"
                   else "(kbytes, -#{flag})"
                   end
            # Left-align description, right-align value
            puts format('%-30s %s', "#{description} #{unit}", formatted)
          rescue Errno::EINVAL
            # Resource not supported on this platform
          end
        end
        return true
      end

      # Get resource info
      resource_info = resource_map[resource_flag]
      unless resource_info
        puts "ulimit: -#{resource_flag}: invalid option"
        return false
      end

      const_sym, divisor, _description = resource_info

      unless Process.const_defined?(const_sym)
        puts "ulimit: -#{resource_flag}: not supported on this platform"
        return false
      end

      const = Process.const_get(const_sym)

      # Display current limit
      if limit_value.nil?
        begin
          soft, hard = Process.getrlimit(const)
          value = use_hard ? hard : soft
          if value == Process::RLIM_INFINITY
            puts 'unlimited'
          else
            puts (value / divisor).to_s
          end
          return true
        rescue Errno::EINVAL
          puts "ulimit: -#{resource_flag}: cannot get limit"
          return false
        end
      end

      # Set new limit
      new_limit = if limit_value == 'unlimited' || limit_value == 'infinity'
                    Process::RLIM_INFINITY
                  elsif limit_value == 'hard'
                    _, hard = Process.getrlimit(const)
                    hard
                  elsif limit_value == 'soft'
                    soft, _ = Process.getrlimit(const)
                    soft
                  elsif limit_value =~ /^\d+$/
                    limit_value.to_i * divisor
                  else
                    puts "ulimit: #{limit_value}: invalid limit"
                    return false
                  end

      begin
        soft, hard = Process.getrlimit(const)
        if use_hard && use_soft
          Process.setrlimit(const, new_limit, new_limit)
        elsif use_hard
          Process.setrlimit(const, soft, new_limit)
        else
          Process.setrlimit(const, new_limit, hard)
        end
        true
      rescue Errno::EPERM
        puts "ulimit: -#{resource_flag}: cannot modify limit"
        false
      rescue Errno::EINVAL
        puts "ulimit: -#{resource_flag}: invalid limit"
        false
      end
    end

    def self.run_suspend(args)
      # suspend [-f]
      # Suspend shell execution
      # -f: force suspend even if login shell

      force = false

      args.each do |arg|
        if arg == '-f'
          force = true
        elsif arg.start_with?('-')
          puts "suspend: #{arg}: invalid option"
          return false
        end
      end

      # Check if this is a login shell (unless -f is specified)
      unless force
        # A login shell typically has $0 starting with '-' or SHLVL=1
        if ENV['SHLVL'] == '1'
          puts 'suspend: cannot suspend a login shell'
          return false
        end
      end

      # Send SIGSTOP to ourselves
      begin
        Process.kill('STOP', Process.pid)
        true
      rescue Errno::EPERM
        puts 'suspend: cannot suspend'
        false
      end
    end

    # Mapping of set -o short flags to long names
    SET_O_LONG_NAMES = {
      'B' => 'braceexpand', 'H' => 'histexpand',
      'e' => 'errexit', 'E' => 'errtrace', 'T' => 'functrace',
      'x' => 'xtrace', 'u' => 'nounset', 'n' => 'noexec', 'v' => 'verbose',
      'f' => 'noglob', 'C' => 'noclobber', 'a' => 'allexport', 'b' => 'notify',
      'h' => 'hashall', 'm' => 'monitor', 'P' => 'physical',
      't' => 'onecmd', 'k' => 'keyword', 'p' => 'privileged',
      'r' => 'restricted'
    }.freeze

    def self.run_shopt(args)
      # shopt [-pqsu] [-o] [optname ...]
      # -s: enable (set) options
      # -u: disable (unset) options
      # -p: print in reusable format
      # -q: quiet mode, return status only
      # -o: restrict to set -o options

      set_mode = false
      unset_mode = false
      print_mode = false
      quiet_mode = false
      set_o_mode = false
      opt_names = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && opt_names.empty?
          arg[1..].each_char do |c|
            case c
            when 's'
              set_mode = true
            when 'u'
              unset_mode = true
            when 'p'
              print_mode = true
            when 'q'
              quiet_mode = true
            when 'o'
              set_o_mode = true
            else
              puts "shopt: -#{c}: invalid option"
              return false
            end
          end
        else
          opt_names << arg
        end
        i += 1
      end

      # Can't use both -s and -u
      if set_mode && unset_mode
        puts 'shopt: cannot set and unset options simultaneously'
        return false
      end

      # When -o is used, work with set -o options instead of shell options
      if set_o_mode
        return run_shopt_set_o(set_mode, unset_mode, print_mode, quiet_mode, opt_names)
      end

      # Helper to get current value of an option
      get_option = lambda do |name|
        if @shell_options.key?(name)
          @shell_options[name]
        elsif SHELL_OPTIONS.key?(name)
          SHELL_OPTIONS[name][0]  # default value
        else
          nil
        end
      end

      # Helper to print an option
      print_option = lambda do |name, value|
        unless quiet_mode
          if print_mode
            puts "shopt #{value ? '-s' : '-u'} #{name}"
          else
            puts "#{name}\t\t#{value ? 'on' : 'off'}"
          end
        end
      end

      # No options specified: list all or specified options
      unless set_mode || unset_mode
        if opt_names.empty?
          # List all options
          SHELL_OPTIONS.each_key do |name|
            value = get_option.call(name)
            print_option.call(name, value)
          end
          return true
        else
          # List specified options
          all_on = true
          opt_names.each do |name|
            unless SHELL_OPTIONS.key?(name)
              puts "shopt: #{name}: invalid shell option name" unless quiet_mode
              return false
            end
            value = get_option.call(name)
            print_option.call(name, value)
            all_on = false unless value
          end
          return all_on  # Return status indicates if all are on
        end
      end

      # Set or unset options
      if opt_names.empty?
        # List options that are on (with -s) or off (with -u)
        SHELL_OPTIONS.each_key do |name|
          value = get_option.call(name)
          if (set_mode && value) || (unset_mode && !value)
            print_option.call(name, value)
          end
        end
        return true
      end

      # Set or unset specified options
      opt_names.each do |name|
        unless SHELL_OPTIONS.key?(name)
          puts "shopt: #{name}: invalid shell option name"
          return false
        end

        # Check for read-only options
        if name == 'login_shell' || name == 'restricted_shell'
          puts "shopt: #{name}: cannot set option"
          return false
        end

        # Compat options are mutually exclusive - enabling one disables others
        if set_mode && COMPAT_OPTIONS.include?(name)
          COMPAT_OPTIONS.each { |opt| @shell_options[opt] = false }
        end

        @shell_options[name] = set_mode
      end

      true
    end

    # Handle shopt -o for set -o style options
    def self.run_shopt_set_o(set_mode, unset_mode, print_mode, quiet_mode, opt_names)
      # Build list of valid set -o option names (long names)
      valid_options = {}
      @set_options.each_key do |key|
        long_name = SET_O_LONG_NAMES[key] || key
        valid_options[long_name] = key
      end

      # Helper to get current value of a set -o option
      get_option = lambda do |name|
        key = valid_options[name]
        return nil unless key
        @set_options[key]
      end

      # Helper to print an option
      print_option = lambda do |name, value|
        unless quiet_mode
          if print_mode
            puts "shopt #{value ? '-so' : '-uo'} #{name}"
          else
            puts "#{name}\t\t#{value ? 'on' : 'off'}"
          end
        end
      end

      # No options specified: list all or specified options
      unless set_mode || unset_mode
        if opt_names.empty?
          # List all set -o options
          valid_options.keys.sort.each do |name|
            value = get_option.call(name)
            print_option.call(name, value)
          end
          return true
        else
          # List specified options
          all_on = true
          opt_names.each do |name|
            unless valid_options.key?(name)
              puts "shopt: #{name}: invalid shell option name" unless quiet_mode
              return false
            end
            value = get_option.call(name)
            print_option.call(name, value)
            all_on = false unless value
          end
          return all_on  # Return status indicates if all are on
        end
      end

      # Set or unset options
      if opt_names.empty?
        # List options that are on (with -s) or off (with -u)
        valid_options.keys.sort.each do |name|
          value = get_option.call(name)
          if (set_mode && value) || (unset_mode && !value)
            print_option.call(name, value)
          end
        end
        return true
      end

      # Set or unset specified options
      opt_names.each do |name|
        unless valid_options.key?(name)
          puts "shopt: #{name}: invalid shell option name"
          return false
        end

        key = valid_options[name]
        @set_options[key] = set_mode
      end

      true
    end

    def self.shopt_enabled?(name)
      # Check @shell_options first (shopt -s)
      if @shell_options.key?(name)
        @shell_options[name]
      # Also check @set_options for options that can be set via both shopt and set -o
      elsif @set_options.key?(name) && @set_options[name]
        true
      elsif SHELL_OPTIONS.key?(name)
        SHELL_OPTIONS[name][0]
      else
        false
      end
    end

    # Set a shell option directly (for internal use)
    def self.set_shell_option(name, value)
      @shell_options[name] = value
    end

    # Normalize zsh option name: lowercase and remove underscores
    # zsh options are case-insensitive and underscores are ignored
    def self.normalize_zsh_option(name)
      name.downcase.gsub('_', '')
    end

    # Find the canonical zsh option name from a possibly non-canonical form
    def self.find_zsh_option(name)
      normalized = normalize_zsh_option(name)

      # Check bash-compatible options first (via ZSH_TO_BASH_OPTIONS mapping)
      ZSH_TO_BASH_OPTIONS.each do |zsh_name, bash_name|
        return [:bash, bash_name] if normalize_zsh_option(zsh_name) == normalized
      end

      # Check zsh-specific options
      ZSH_OPTIONS.each_key do |opt_name|
        return [:zsh, opt_name] if normalize_zsh_option(opt_name) == normalized
      end

      # Not found
      nil
    end

    # Get the current value of a zsh option
    def self.zsh_option_enabled?(name)
      result = find_zsh_option(name)
      return false unless result

      type, canonical_name = result
      if type == :bash
        shopt_enabled?(canonical_name)
      else
        if @zsh_options.key?(canonical_name)
          @zsh_options[canonical_name]
        else
          ZSH_OPTIONS[canonical_name][0]  # default value
        end
      end
    end

    # Set a zsh option directly (for internal use)
    def self.set_zsh_option(name, value)
      result = find_zsh_option(name)
      return false unless result

      type, canonical_name = result
      if type == :bash
        @shell_options[canonical_name] = value
      else
        @zsh_options[canonical_name] = value
      end
      true
    end

    # setopt [+-options] [name ...]
    # Enable shell options (zsh-style)
    def self.run_setopt(args)
      # No arguments: list all enabled options
      if args.empty?
        list_enabled_zsh_options
        return true
      end

      success = true
      args.each do |arg|
        # Handle NO prefix (e.g., noautocd -> disable autocd)
        if arg.downcase.start_with?('no')
          # Try without the 'no' prefix
          opt_without_no = arg[2..]
          result = find_zsh_option(opt_without_no)
          if result
            type, canonical_name = result
            if type == :bash
              @shell_options[canonical_name] = false
            else
              @zsh_options[canonical_name] = false
            end
            next
          end
        end

        result = find_zsh_option(arg)
        if result
          type, canonical_name = result
          if type == :bash
            @shell_options[canonical_name] = true
          else
            @zsh_options[canonical_name] = true
          end
        else
          $stderr.puts "setopt: no such option: #{arg}"
          success = false
        end
      end

      success
    end

    # unsetopt [+-options] [name ...]
    # Disable shell options (zsh-style)
    def self.run_unsetopt(args)
      # No arguments: list all disabled options
      if args.empty?
        list_disabled_zsh_options
        return true
      end

      success = true
      args.each do |arg|
        # Handle NO prefix (e.g., noautocd -> enable autocd, inverting the disable)
        if arg.downcase.start_with?('no')
          # Try without the 'no' prefix
          opt_without_no = arg[2..]
          result = find_zsh_option(opt_without_no)
          if result
            type, canonical_name = result
            if type == :bash
              @shell_options[canonical_name] = true
            else
              @zsh_options[canonical_name] = true
            end
            next
          end
        end

        result = find_zsh_option(arg)
        if result
          type, canonical_name = result
          if type == :bash
            @shell_options[canonical_name] = false
          else
            @zsh_options[canonical_name] = false
          end
        else
          $stderr.puts "unsetopt: no such option: #{arg}"
          success = false
        end
      end

      success
    end

    # List all currently enabled zsh options
    def self.list_enabled_zsh_options
      enabled = []

      # Bash-compatible options that are enabled
      ZSH_TO_BASH_OPTIONS.values.uniq.each do |bash_name|
        enabled << bash_name if shopt_enabled?(bash_name)
      end

      # Zsh-specific options that are enabled
      ZSH_OPTIONS.each do |name, (default, _desc)|
        value = @zsh_options.key?(name) ? @zsh_options[name] : default
        enabled << name if value
      end

      enabled.sort.each { |name| puts name }
    end

    # List all currently disabled zsh options
    def self.list_disabled_zsh_options
      disabled = []

      # Bash-compatible options that are disabled
      ZSH_TO_BASH_OPTIONS.values.uniq.each do |bash_name|
        disabled << bash_name unless shopt_enabled?(bash_name)
      end

      # Zsh-specific options that are disabled
      ZSH_OPTIONS.each do |name, (default, _desc)|
        value = @zsh_options.key?(name) ? @zsh_options[name] : default
        disabled << name unless value
      end

      disabled.sort.each { |name| puts name }
    end

    # Get current compatibility level from RUBISH_COMPAT or shopt compat* options
    # Returns a numeric version (e.g., 10 for 1.0) or nil if not set
    def self.compat_level
      # Check RUBISH_COMPAT environment variable first, then BASH_COMPAT as fallback
      rubish_compat = ENV['RUBISH_COMPAT']
      rubish_compat = ENV['BASH_COMPAT'] if rubish_compat.nil? || rubish_compat.empty?
      if rubish_compat && !rubish_compat.empty?
        # Convert "1.0" to 10, "1.1" to 11, etc.
        parts = rubish_compat.split('.')
        if parts.length == 2
          return parts[0].to_i * 10 + parts[1].to_i
        elsif parts.length == 1
          return parts[0].to_i * 10
        end
      end

      # Check shopt compat* options
      COMPAT_OPTIONS.each do |opt|
        if shopt_enabled?(opt)
          # Extract version number from option name (compat10 -> 10)
          return opt.sub('compat', '').to_i
        end
      end

      nil
    end

    # Check if running in a specific compatibility mode
    def self.compat_level?(level)
      current = compat_level
      current && current <= level
    end

    # Get BASH_COMPAT value as a string (e.g., "5.1" or "51")
    # Returns empty string if no compat level is set (default mode)
    def self.bash_compat
      level = compat_level
      return '' unless level

      # Convert level to bash-style format (e.g., 51 -> "5.1" or "51")
      major = level / 10
      minor = level % 10
      "#{major}.#{minor}"
    end

    # Set compatibility level from BASH_COMPAT value
    # Accepts: "5.1", "51", 5.1, 51
    def self.set_bash_compat(value)
      return clear_compat_level if value.nil? || value.to_s.empty?

      str = value.to_s.strip
      level = if str.include?('.')
                # Format: "5.1" -> 51
                parts = str.split('.')
                return clear_compat_level unless parts.length == 2
                parts[0].to_i * 10 + parts[1].to_i
              else
                # Format: "51" -> 51
                str.to_i
              end

      # Validate the level corresponds to a valid compat option
      compat_opt = "compat#{level}"
      unless SHELL_OPTIONS.key?(compat_opt)
        $stderr.puts "BASH_COMPAT: #{value}: invalid value"
        return clear_compat_level
      end

      # Clear all compat options and enable the specified one
      COMPAT_OPTIONS.each { |opt| @shell_options[opt] = false }
      @shell_options[compat_opt] = true
    end

    # Clear all compat levels (return to default)
    def self.clear_compat_level
      COMPAT_OPTIONS.each { |opt| @shell_options[opt] = false }
    end

    # Set compatibility level (used when RUBISH_COMPAT is assigned)
    def self.set_compat_level(version)
      return unless version

      # Clear all compat options first
      COMPAT_OPTIONS.each { |opt| @shell_options[opt] = false }

      # Parse version string
      parts = version.to_s.split('.')
      level = if parts.length == 2
                parts[0].to_i * 10 + parts[1].to_i
              elsif parts.length == 1
                parts[0].to_i * 10
              else
                return
              end

      # Enable the appropriate compat option
      compat_opt = "compat#{level}"
      @shell_options[compat_opt] = true if SHELL_OPTIONS.key?(compat_opt)
    end

    # Check if POSIX mode is enabled via POSIXLY_CORRECT environment variable
    # In bash, POSIX mode is enabled when POSIXLY_CORRECT is set (even to empty string)
    def self.posix_mode?
      ENV.key?('POSIXLY_CORRECT')
    end

    # READLINE_LINE - contents of the readline buffer during bind -x execution
    def self.readline_line
      @readline_line_getter&.call || ''
    end

    def self.readline_line=(value)
      @readline_line_setter&.call(value.to_s)
    end

    # READLINE_POINT - cursor position (index) in READLINE_LINE during bind -x execution
    def self.readline_point
      @readline_point_getter&.call || 0
    end

    def self.readline_point=(value)
      @readline_point_setter&.call(value.to_i)
    end

    # READLINE_MARK - mark position in READLINE_LINE during bind -x execution
    def self.readline_mark
      @readline_mark_getter&.call || 0
    end

    def self.readline_mark=(value)
      @readline_mark_setter&.call(value.to_i)
    end

    # Track dynamically loaded builtins
    @loaded_builtins = {}  # name => { file: path, proc: callable }

    class << self
      attr_reader :loaded_builtins
    end

    def self.run_enable(args)
      # enable [-a] [-dnps] [-f filename] [name ...]
      # -a: list all builtins (enabled and disabled)
      # -n: disable builtins
      # -p: print in reusable format
      # -s: list only POSIX special builtins
      # -d: remove a builtin loaded with -f
      # -f: load builtin from Ruby file (searches RUBISH_LOADABLES_PATH)

      show_all = false
      disable_mode = false
      print_mode = false
      special_only = false
      delete_mode = false
      load_file = nil
      names = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && names.empty?
          chars = arg[1..].chars
          j = 0
          while j < chars.length
            c = chars[j]
            case c
            when 'a'
              show_all = true
            when 'n'
              disable_mode = true
            when 'p'
              print_mode = true
            when 's'
              special_only = true
            when 'd'
              delete_mode = true
            when 'f'
              # -f requires a filename argument
              if j + 1 < chars.length
                # Filename is rest of this arg
                load_file = chars[j + 1..].join
                break
              elsif i + 1 < args.length
                # Filename is next arg
                i += 1
                load_file = args[i]
              else
                puts 'enable: -f: option requires an argument'
                return false
              end
            else
              puts "enable: -#{c}: invalid option"
              return false
            end
            j += 1
          end
        else
          names << arg
        end
        i += 1
      end

      # POSIX special builtins
      special_builtins = %w[. : break continue eval exec exit export readonly return set shift trap unset].freeze

      # Handle -f: load builtins from file
      if load_file && names.empty?
        puts 'enable: -f: builtin name required'
        return false
      end

      if load_file && !names.empty?
        file_path = find_loadable_file(load_file)
        unless file_path
          puts "enable: #{load_file}: cannot open: No such file or directory"
          return false
        end

        begin
          # Load the Ruby file - it should define methods or Procs
          content = File.read(file_path)
          # Evaluate in a module to isolate the definitions
          mod = Module.new
          mod.module_eval(content, file_path, 1)

          names.each do |name|
            # Look for a method or constant with the builtin name
            method_name = "run_#{name.tr('-', '_')}"
            if mod.respond_to?(method_name)
              @loaded_builtins[name] = {file: file_path, callable: mod.method(method_name)}
              @dynamic_commands << name unless @dynamic_commands.include?(name)
            elsif mod.const_defined?(name.upcase.tr('-', '_'), false)
              callable = mod.const_get(name.upcase.tr('-', '_'))
              @loaded_builtins[name] = {file: file_path, callable: callable}
              @dynamic_commands << name unless @dynamic_commands.include?(name)
            else
              puts "enable: #{name}: not found in #{load_file}"
              return false
            end
          end
          return true
        rescue SyntaxError, StandardError => e
          puts "enable: #{load_file}: #{e.message}"
          return false
        end
      end

      # Handle -d: delete (unload) loaded builtins
      if delete_mode && !names.empty?
        names.each do |name|
          if @loaded_builtins.key?(name)
            @loaded_builtins.delete(name)
            @dynamic_commands.delete(name)
          else
            puts "enable: #{name}: not a dynamically loaded builtin"
            return false
          end
        end
        return true
      end

      # Helper to print a builtin
      print_builtin = lambda do |name, enabled|
        if print_mode
          puts "enable #{enabled ? '' : '-n '}#{name}"
        else
          puts "enable #{enabled ? '' : '-n '}#{name}"
        end
      end

      # No names specified: list builtins
      if names.empty?
        builtins_to_show = special_only ? special_builtins : all_commands

        builtins_to_show.each do |name|
          next unless builtin_exists?(name)

          enabled = !@disabled_builtins.include?(name)

          if show_all
            print_builtin.call(name, enabled)
          elsif disable_mode
            # -n without names: show disabled builtins
            print_builtin.call(name, enabled) unless enabled
          else
            # No flags: show enabled builtins
            print_builtin.call(name, enabled) if enabled
          end
        end
        return true
      end

      # Enable or disable specified builtins
      names.each do |name|
        unless builtin_exists?(name)
          puts "enable: #{name}: not a shell builtin"
          return false
        end

        if disable_mode
          @disabled_builtins.add(name)
        else
          @disabled_builtins.delete(name)
        end
      end

      true
    end

    def self.find_loadable_file(filename)
      # If absolute path, use it directly
      return filename if filename.start_with?('/') && File.file?(filename)

      # If relative path with directory component, use it directly
      if filename.include?('/') && File.file?(filename)
        return File.expand_path(filename)
      end

      # Search in RUBISH_LOADABLES_PATH (or BASH_LOADABLES_PATH for bash compatibility)
      loadables_path = ENV['RUBISH_LOADABLES_PATH'] || ENV['BASH_LOADABLES_PATH']
      if loadables_path && !loadables_path.empty?
        loadables_path.split(':').each do |dir|
          next if dir.empty?

          candidate = File.join(dir, filename)
          return candidate if File.file?(candidate)

          # Also try with .rb extension
          candidate_rb = "#{candidate}.rb"
          return candidate_rb if File.file?(candidate_rb)
        end
      end

      # Not found
      nil
    end

    def self.run_caller(args)
      # caller [expr]
      # Display the call stack of the current subroutine call
      # With expr: display stack frame at that depth (0 = current)
      # Returns false if no call stack or expr is out of range

      # Check for invalid options
      if args.any? { |arg| arg.start_with?('-') }
        puts "caller: #{args.first}: invalid option"
        return false
      end

      # Get the frame number (default 0)
      frame = 0
      if args.any?
        arg = args.first
        unless arg =~ /^\d+$/
          puts "caller: #{arg}: invalid number"
          return false
        end
        frame = arg.to_i
      end

      # Check if we have a call stack
      if @call_stack.empty?
        return false
      end

      # Check if frame is in range
      if frame >= @call_stack.length
        return false
      end

      # Get the frame (stack is stored with most recent first)
      # But caller 0 should be the immediate caller, so we need to reverse
      stack_frame = @call_stack[-(frame + 1)]
      return false unless stack_frame

      line_number, function_name, filename = stack_frame
      puts "#{line_number} #{function_name} #{filename}"
      true
    end

    def self.push_call_frame(line_number, function_name, filename)
      @call_stack.push([line_number, function_name, filename])
    end

    def self.pop_call_frame
      @call_stack.pop
    end

    def self.clear_call_stack
      @call_stack.clear
    end

    def self.run_complete(args)
      # complete [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist]
      #          [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix]
      #          [-p] [-r] [name ...]
      # Define completion specifications for commands

      # Parse options
      print_mode = false
      remove_mode = false
      spec = {
        actions: [],
        wordlist: nil,
        function: nil,
        command: nil,
        globpat: nil,
        filterpat: nil,
        prefix: nil,
        suffix: nil,
        options: []
      }
      names = []

      # Action flags mapping
      action_flags = {
        'a' => :alias,
        'b' => :builtin,
        'c' => :command,
        'd' => :directory,
        'e' => :export,
        'f' => :file,
        'g' => :group,
        'j' => :job,
        'k' => :keyword,
        's' => :service,
        'u' => :user,
        'v' => :variable
      }

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && names.empty?
          case arg
          when '-p'
            print_mode = true
          when '-r'
            remove_mode = true
          when '-o'
            i += 1
            spec[:options] << args[i] if args[i]
          when '-A'
            i += 1
            spec[:actions] << args[i].to_sym if args[i]
          when '-G'
            i += 1
            spec[:globpat] = args[i]
          when '-W'
            i += 1
            spec[:wordlist] = args[i]
          when '-F'
            i += 1
            spec[:function] = args[i]
          when '-C'
            i += 1
            spec[:command] = args[i]
          when '-X'
            i += 1
            spec[:filterpat] = args[i]
          when '-P'
            i += 1
            spec[:prefix] = args[i]
          when '-S'
            i += 1
            spec[:suffix] = args[i]
          else
            # Handle combined flags like -df
            arg[1..].each_char do |c|
              if action_flags.key?(c)
                spec[:actions] << action_flags[c]
              else
                puts "complete: -#{c}: invalid option"
                return false
              end
            end
          end
        else
          names << arg
        end
        i += 1
      end

      # Print mode
      if print_mode
        if names.empty?
          # Print all completions
          @completions.each do |name, s|
            puts format_completion_spec(name, s)
          end
        else
          # Print specified completions
          names.each do |name|
            if @completions.key?(name)
              puts format_completion_spec(name, @completions[name])
            else
              puts "complete: #{name}: no completion specification"
              return false
            end
          end
        end
        return true
      end

      # Remove mode
      if remove_mode
        if names.empty?
          # Remove all completions
          @completions.clear
        else
          names.each do |name|
            @completions.delete(name)
          end
        end
        return true
      end

      # Define completions
      if names.empty?
        puts 'complete: usage: complete [-abcdefgjksuv] [-pr] [-o option] [-A action] [name ...]'
        return false
      end

      names.each do |name|
        @completions[name] = spec.dup
      end

      true
    end

    def self.format_completion_spec(name, spec)
      parts = ['complete']

      (spec[:actions] || []).each do |action|
        case action
        when :alias then parts << '-a'
        when :builtin then parts << '-b'
        when :command then parts << '-c'
        when :directory then parts << '-d'
        when :export then parts << '-e'
        when :file then parts << '-f'
        when :group then parts << '-g'
        when :job then parts << '-j'
        when :keyword then parts << '-k'
        when :service then parts << '-s'
        when :user then parts << '-u'
        when :variable then parts << '-v'
        else
          parts << "-A #{action}"
        end
      end

      (spec[:options] || []).each { |o| parts << "-o #{o}" }
      parts << "-G #{spec[:globpat]}" if spec[:globpat]
      parts << "-W '#{spec[:wordlist]}'" if spec[:wordlist]
      parts << "-F #{spec[:function]}" if spec[:function]
      parts << "-C #{spec[:command]}" if spec[:command]
      parts << "-X '#{spec[:filterpat]}'" if spec[:filterpat]
      parts << "-P '#{spec[:prefix]}'" if spec[:prefix]
      parts << "-S '#{spec[:suffix]}'" if spec[:suffix]

      parts << name
      parts.join(' ')
    end

    def self.run_compgen(args)
      # compgen [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist]
      #         [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [word]
      # Generate completions matching word

      spec = {
        actions: [],
        wordlist: nil,
        function: nil,
        command: nil,
        globpat: nil,
        filterpat: nil,
        prefix: nil,
        suffix: nil,
        options: []
      }
      word = ''

      action_flags = {
        'a' => :alias,
        'b' => :builtin,
        'c' => :command,
        'd' => :directory,
        'e' => :export,
        'f' => :file,
        'g' => :group,
        'j' => :job,
        'k' => :keyword,
        's' => :service,
        'u' => :user,
        'v' => :variable
      }

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-')
          case arg
          when '-o'
            i += 1
            spec[:options] << args[i] if args[i]
          when '-A'
            i += 1
            spec[:actions] << args[i].to_sym if args[i]
          when '-G'
            i += 1
            spec[:globpat] = args[i]
          when '-W'
            i += 1
            spec[:wordlist] = args[i]
          when '-F'
            i += 1
            spec[:function] = args[i]
          when '-C'
            i += 1
            spec[:command] = args[i]
          when '-X'
            i += 1
            spec[:filterpat] = args[i]
          when '-P'
            i += 1
            spec[:prefix] = args[i]
          when '-S'
            i += 1
            spec[:suffix] = args[i]
          else
            arg[1..].each_char do |c|
              if action_flags.key?(c)
                spec[:actions] << action_flags[c]
              else
                puts "compgen: -#{c}: invalid option"
                return false
              end
            end
          end
        else
          word = arg
        end
        i += 1
      end

      completions = generate_completions(spec, word)

      completions.each { |c| puts c }
      !completions.empty?
    end

    def self.generate_completions(spec, word = '')
      results = []

      spec[:actions].each do |action|
        case action
        when :alias
          results.concat(@aliases.keys.select { |a| a.start_with?(word) })
        when :arrayvar
          # Array variable names
          results.concat(@arrays.keys.select { |a| a.start_with?(word) })
        when :binding
          # Readline key binding names
          results.concat(READLINE_FUNCTIONS.select { |f| f.start_with?(word) })
        when :builtin
          results.concat(COMMANDS.select { |c| c.start_with?(word) })
        when :command
          # Commands from PATH
          ENV['PATH'].to_s.split(':').each do |dir|
            next unless Dir.exist?(dir)

            Dir.entries(dir).each do |entry|
              next if entry.start_with?('.')

              path = File.join(dir, entry)
              results << entry if entry.start_with?(word) && File.executable?(path)
            end
          rescue Errno::EACCES
            # Skip directories we can't read
          end
          results.concat(COMMANDS.select { |c| c.start_with?(word) })
        when :directory
          pattern = word.empty? ? '*' : "#{word}*"
          Dir.glob(pattern).each do |entry|
            results << entry if File.directory?(entry)
          end
        when :disabled
          # Disabled builtin names
          results.concat(@disabled_builtins.to_a.select { |b| b.start_with?(word) })
        when :enabled
          # Enabled builtin names (builtins not in disabled list)
          enabled = COMMANDS.reject { |c| @disabled_builtins.include?(c) }
          results.concat(enabled.select { |c| c.start_with?(word) })
        when :export
          ENV.keys.select { |k| k.start_with?(word) }.each { |k| results << k }
        when :file
          pattern = word.empty? ? '*' : "#{word}*"
          results.concat(Dir.glob(pattern))
        when :function
          # Shell function names
          functions = @function_lister&.call || {}
          results.concat(functions.keys.select { |f| f.start_with?(word) })
        when :group
          begin
            Etc.group { |g| results << g.name if g.name.start_with?(word) }
          rescue StandardError
            # Etc may not be available
          end
        when :helptopic
          # Help topics (builtins and special topics)
          results.concat(COMMANDS.select { |c| c.start_with?(word) })
        when :hostname
          # Hostnames from /etc/hosts and HOSTFILE
          results.concat(get_hostnames.select { |h| h.start_with?(word) })
        when :job
          JobManager.instance.all.each do |job|
            job_spec = "%#{job.id}"
            results << job_spec if job_spec.start_with?(word)
          end
        when :keyword
          # Shell reserved words
          keywords = %w[if then else elif fi case esac for select while until do done
                        in function time { } ! [[ ]] coproc]
          results.concat(keywords.select { |k| k.start_with?(word) })
        when :running
          # Running jobs
          JobManager.instance.all.each do |job|
            next unless job.running?
            job_spec = "%#{job.id}"
            results << job_spec if job_spec.start_with?(word)
          end
        when :service
          # Service names (from /etc/services)
          results.concat(get_services.select { |s| s.start_with?(word) })
        when :setopt
          # set -o option names
          set_options = %w[allexport braceexpand emacs errexit errtrace functrace hashall
                           histexpand history ignoreeof interactive-comments keyword monitor
                           noclobber noexec noglob nolog notify nounset onecmd physical
                           pipefail posix privileged verbose vi xtrace]
          results.concat(set_options.select { |o| o.start_with?(word) })
        when :shopt
          # shopt option names
          results.concat(SHELL_OPTIONS.keys.select { |o| o.start_with?(word) })
        when :signal
          # Signal names
          signals = %w[HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1 SEGV USR2 PIPE
                       ALRM TERM STKFLT CHLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ
                       VTALRM PROF WINCH IO PWR SYS EXIT ERR DEBUG RETURN]
          results.concat(signals.select { |s| s.start_with?(word.upcase) })
        when :stopped
          # Stopped jobs
          JobManager.instance.all.each do |job|
            next unless job.stopped?
            job_spec = "%#{job.id}"
            results << job_spec if job_spec.start_with?(word)
          end
        when :user
          begin
            Etc.passwd { |u| results << u.name if u.name.start_with?(word) }
          rescue StandardError
            # Etc may not be available
          end
        when :variable
          ENV.keys.select { |k| k.start_with?(word) }.each { |k| results << k }
        end
      end

      # Wordlist (-W)
      if spec[:wordlist]
        words = spec[:wordlist].split
        results.concat(words.select { |w| w.start_with?(word) })
      end

      # Function (-F) - call a function to generate completions
      if spec[:function]
        func_results = generate_function_completions(spec[:function], word)
        results.concat(func_results.select { |r| r.start_with?(word) })
      end

      # Command (-C) - execute a command to generate completions
      if spec[:command]
        cmd_results = generate_command_completions(spec[:command], word)
        results.concat(cmd_results.select { |r| r.start_with?(word) })
      end

      # Glob pattern (-G)
      if spec[:globpat]
        results.concat(Dir.glob(spec[:globpat]).select { |f| f.start_with?(word) })
      end

      # Filter pattern (-X) - remove matches
      if spec[:filterpat]
        pattern = glob_to_regex(spec[:filterpat])
        results.reject! { |r| r.match?(pattern) }
      end

      # Add prefix/suffix (-P/-S)
      if spec[:prefix] || spec[:suffix]
        results.map! do |r|
          "#{spec[:prefix]}#{r}#{spec[:suffix]}"
        end
      end

      results.uniq.sort
    end

    # Generate completions by calling a function (-F)
    def self.generate_function_completions(function_name, word)
      # Save current COMPREPLY
      saved_compreply = @compreply.dup

      # Clear COMPREPLY for the function
      @compreply = []

      # Set up completion context if not already set
      # The function expects: $1 = command name, $2 = word being completed, $3 = previous word
      cmd = @comp_words&.first || ''
      prev = @comp_cword && @comp_cword > 0 ? (@comp_words[@comp_cword - 1] || '') : ''

      begin
        # Try builtin completion function first
        if builtin_completion_function?(function_name)
          call_builtin_completion_function(function_name, cmd, word, prev)
        elsif @function_caller
          # Call user-defined function
          @function_caller.call(function_name, [cmd, word, prev])
        end

        # Return the results from COMPREPLY
        @compreply.dup
      ensure
        # Restore COMPREPLY
        @compreply = saved_compreply
      end
    end

    # Generate completions by executing a command (-C)
    def self.generate_command_completions(command, word)
      results = []

      begin
        # Set up environment variables for the command
        # COMP_LINE, COMP_POINT, COMP_WORDS, COMP_CWORD should already be set
        # The command output (one completion per line) becomes the completions

        output = `#{command} 2>/dev/null`
        results = output.split("\n").map(&:strip).reject(&:empty?)
      rescue => e
        # Command execution failed
        $stderr.puts "compgen: #{command}: #{e.message}" if ENV['RUBISH_DEBUG']
      end

      results
    end

    # Convert a shell glob pattern to a regex for -X filter
    def self.glob_to_regex(pattern)
      # Handle ! at the start (negation in bash, but for -X it means "remove if matches")
      pattern = pattern.sub(/^!/, '')

      # Convert glob to regex
      regex_str = pattern.gsub(/[.+^${}()|\\]/) { |c| "\\#{c}" }
                         .gsub('*', '.*')
                         .gsub('?', '.')
                         .gsub(/\[!/, '[^')

      Regexp.new("^#{regex_str}$")
    end

    # Get hostnames from /etc/hosts and HOSTFILE
    def self.get_hostnames
      hostnames = Set.new

      # Read /etc/hosts
      if File.exist?('/etc/hosts')
        begin
          File.readlines('/etc/hosts').each do |line|
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            parts = line.split(/\s+/)
            next if parts.length < 2

            # Skip IP, add hostnames
            parts[1..].each { |h| hostnames << h }
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      # Read HOSTFILE if set
      hostfile = ENV['HOSTFILE']
      if hostfile && File.exist?(hostfile)
        begin
          File.readlines(hostfile).each do |line|
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            parts = line.split(/\s+/)
            next if parts.length < 2

            parts[1..].each { |h| hostnames << h }
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      hostnames.to_a
    end

    # Get service names from /etc/services
    def self.get_services
      services = Set.new

      if File.exist?('/etc/services')
        begin
          File.readlines('/etc/services').each do |line|
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            # Format: service_name port/protocol [aliases...]
            name = line.split(/\s+/).first
            services << name if name && !name.empty?
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      services.to_a
    end

    def self.get_completion_spec(name)
      spec = @completions[name]
      return spec if spec

      # progcomp_alias: if name is an alias, use completion spec for the aliased command
      if shopt_enabled?('progcomp_alias') && @aliases.key?(name)
        # Get the first word of the alias expansion
        alias_value = @aliases[name]
        first_word = alias_value.split(/\s+/).first
        # Avoid infinite loop if alias points to itself
        return nil if first_word == name
        return @completions[first_word]
      end

      nil
    end

    def self.clear_completions
      @completions.clear
    end

    # Check if a function name is a builtin completion function
    def self.builtin_completion_function?(name)
      @builtin_completion_functions.key?(name)
    end

    # Call a builtin completion function
    # Returns true if function was called, false if not found
    def self.call_builtin_completion_function(name, cmd, cur, prev)
      func = @builtin_completion_functions[name]
      return false unless func
      func.call(cmd, cur, prev)
      true
    end

    # Register builtin completion functions
    def self.register_builtin_completion_functions
      # _git - Git completion
      @builtin_completion_functions['_git'] = ->(cmd, cur, prev) { _git_completion(cmd, cur, prev) }

      # _ssh - SSH completion
      @builtin_completion_functions['_ssh'] = ->(cmd, cur, prev) { _ssh_completion(cmd, cur, prev) }

      # _cd - Directory completion
      @builtin_completion_functions['_cd'] = ->(cmd, cur, prev) { _cd_completion(cmd, cur, prev) }

      # _make - Make target completion
      @builtin_completion_functions['_make'] = ->(cmd, cur, prev) { _make_completion(cmd, cur, prev) }

      # _man - Man page completion
      @builtin_completion_functions['_man'] = ->(cmd, cur, prev) { _man_completion(cmd, cur, prev) }

      # _kill - Process completion
      @builtin_completion_functions['_kill'] = ->(cmd, cur, prev) { _kill_completion(cmd, cur, prev) }
    end

    # Initialize builtin completion functions on load
    register_builtin_completion_functions

    # Set up default completion specifications for common commands
    # This registers the builtin completion functions with the completion system
    def self.setup_default_completions
      # Git completion
      @completions['git'] = {actions: [], function: '_git'}

      # SSH/SCP/SFTP completion
      @completions['ssh'] = {actions: [], function: '_ssh'}
      @completions['scp'] = {actions: [], function: '_ssh'}
      @completions['sftp'] = {actions: [], function: '_ssh'}

      # CD completion (directories only)
      @completions['cd'] = {actions: [], function: '_cd'}
      @completions['pushd'] = {actions: [], function: '_cd'}

      # Make completion
      @completions['make'] = {actions: [], function: '_make'}
      @completions['gmake'] = {actions: [], function: '_make'}

      # Man page completion
      @completions['man'] = {actions: [], function: '_man'}

      # Kill completion
      @completions['kill'] = {actions: [], function: '_kill'}
      @completions['killall'] = {actions: [], function: '_kill'}
      @completions['pkill'] = {actions: [], function: '_kill'}
    end

    # ==========================================================================
    # Git completion function
    # ==========================================================================
    GIT_COMMANDS = %w[
      add am annotate archive bisect blame branch bundle cat-file
      check-attr check-ignore check-mailmap checkout checkout-index
      cherry cherry-pick citool clean clone column commit config count-objects
      credential daemon describe diff diff-files diff-index diff-tree
      difftool fast-export fast-import fetch fetch-pack filter-branch
      fmt-merge-msg for-each-ref format-patch fsck gc get-tar-commit-id
      grep gui hash-object help imap-send index-pack init init-db instaweb
      interpret-trailers log ls-files ls-remote ls-tree mailinfo mailsplit
      maintenance merge merge-base merge-file merge-index merge-octopus
      merge-one-file merge-ours merge-recursive merge-resolve merge-subtree
      merge-tree mergetool mktag mktree mv name-rev notes pack-objects
      pack-redundant pack-refs patch-id prune prune-packed pull push
      quiltimport range-diff read-tree rebase reflog remote repack replace
      request-pull rerere reset restore rev-list rev-parse revert rm
      send-email send-pack shortlog show show-branch show-index show-ref
      sparse-checkout stash status stripspace submodule switch symbolic-ref
      tag unpack-file unpack-objects update-index update-ref update-server-info
      upload-archive upload-pack var verify-commit verify-pack verify-tag
      whatchanged worktree write-tree
    ].freeze

    # Common git options that apply to most commands
    GIT_COMMON_OPTIONS = %w[
      --version --help -C --git-dir --work-tree --bare --no-replace-objects
      --literal-pathspecs --glob-pathspecs --noglob-pathspecs --icase-pathspecs
      --no-optional-locks -c --exec-path --html-path --man-path --info-path
      --paginate --no-pager --config-env
    ].freeze

    def self._git_completion(cmd, cur, prev)
      words = @comp_words
      cword = @comp_cword

      # Determine git subcommand
      subcommand = nil
      subcommand_idx = nil
      words.each_with_index do |word, idx|
        next if idx == 0  # Skip 'git'
        next if word.start_with?('-')  # Skip options

        # Found subcommand
        subcommand = word
        subcommand_idx = idx
        break
      end

      if subcommand.nil? || cword <= (subcommand_idx || 1)
        # Complete git subcommands or top-level options
        if cur.start_with?('-')
          @compreply = GIT_COMMON_OPTIONS.select { |opt| opt.start_with?(cur) }
        else
          @compreply = GIT_COMMANDS.select { |c| c.start_with?(cur) }
        end
        return
      end

      # Complete based on subcommand
      case subcommand
      when 'add'
        _git_complete_add(cur, prev)
      when 'branch'
        _git_complete_branch(cur, prev)
      when 'checkout', 'switch'
        _git_complete_checkout(cur, prev)
      when 'commit'
        _git_complete_commit(cur, prev)
      when 'diff'
        _git_complete_diff(cur, prev)
      when 'fetch', 'pull', 'push'
        _git_complete_remote_branch(cur, prev, subcommand)
      when 'log', 'show'
        _git_complete_log(cur, prev)
      when 'merge', 'rebase'
        _git_complete_refs(cur)
      when 'remote'
        _git_complete_remote(cur, prev, words, cword, subcommand_idx)
      when 'reset'
        _git_complete_reset(cur, prev)
      when 'revert'
        _git_complete_refs(cur)
      when 'stash'
        _git_complete_stash(cur, prev, words, cword, subcommand_idx)
      when 'tag'
        _git_complete_tag(cur, prev)
      else
        # Default: complete files and refs
        _git_complete_refs(cur)
        _git_complete_files(cur)
      end
    end

    def self._git_complete_add(cur, prev)
      case prev
      when '-p', '--patch'
        _git_complete_files(cur)
      else
        if cur.start_with?('-')
          opts = %w[-n --dry-run -v --verbose -i --interactive -p --patch
                    -e --edit -f --force -u --update -A --all --no-ignore-removal
                    --no-all --ignore-removal -N --intent-to-add --refresh
                    --ignore-errors --ignore-missing --sparse --pathspec-from-file=
                    --pathspec-file-nul --renormalize --chmod=+x --chmod=-x]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_files(cur)
        end
      end
    end

    def self._git_complete_branch(cur, prev)
      case prev
      when '-d', '-D', '--delete', '-m', '-M', '--move', '-c', '-C', '--copy'
        _git_complete_local_branches(cur)
      when '-u', '--set-upstream-to'
        _git_complete_remote_refs(cur)
      when '-t', '--track'
        _git_complete_remote_refs(cur)
      else
        if cur.start_with?('-')
          opts = %w[-a --all -d -D --delete -f --force -i --ignore-case -l --list
                    -m -M --move -c -C --copy -r --remotes --show-current -v --verbose
                    -q --quiet --track -t --no-track --set-upstream-to -u --unset-upstream
                    --edit-description --contains --no-contains --merged --no-merged
                    --column --no-column --sort= --points-at --format= --color --no-color]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_local_branches(cur)
        end
      end
    end

    def self._git_complete_checkout(cur, prev)
      case prev
      when '-b', '-B', '--orphan'
        # New branch name - don't complete
        @compreply = []
      when '--'
        _git_complete_files(cur)
      else
        if cur.start_with?('-')
          opts = %w[-q --quiet -f --force -b -B --detach --ours --theirs
                    -m --merge -l --track -t --no-track --orphan --ignore-other-worktrees
                    --recurse-submodules --no-recurse-submodules --progress --no-progress
                    --overlay --no-overlay --pathspec-from-file= --pathspec-file-nul]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_refs(cur)
        end
      end
    end

    def self._git_complete_commit(cur, prev)
      case prev
      when '-C', '-c', '--reuse-message', '--reedit-message', '--fixup', '--squash'
        _git_complete_refs(cur)
      when '-m', '--message'
        @compreply = []  # Message string
      when '-F', '--file', '--pathspec-from-file'
        _git_complete_files(cur)
      when '--author'
        @compreply = []  # Author string
      when '--date'
        @compreply = []  # Date string
      when '--cleanup'
        @compreply = %w[strip whitespace verbatim scissors default].select { |opt| opt.start_with?(cur) }
      else
        if cur.start_with?('-')
          opts = %w[-a --all -p --patch --reset-author -s --signoff -n --no-verify
                    -v --verbose -u --untracked-files -q --quiet --dry-run
                    --short --branch --porcelain --long -z --null --status
                    --no-status -F --file -m --message --author --date
                    -C --reuse-message -c --reedit-message --fixup --squash
                    --amend --no-edit -e --edit --cleanup= --trailer
                    --only -i --include --allow-empty --allow-empty-message]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_files(cur)
        end
      end
    end

    def self._git_complete_diff(cur, prev)
      if cur.start_with?('-')
        opts = %w[-p -u --patch -U --unified= --raw --patch-with-raw --stat
                  --numstat --shortstat --dirstat --summary --patch-with-stat
                  -z --name-only --name-status --color --no-color --color-moved
                  --word-diff --color-words --no-renames --check --full-index
                  --binary -a --text -R --ignore-space-change -w
                  --ignore-all-space -b --ignore-blank-lines --inter-hunk-context=
                  --patience --histogram --diff-algorithm= --anchored=
                  --minimal --no-index --cached --staged -S -G --pickaxe-regex]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _git_complete_refs(cur)
        _git_complete_files(cur)
      end
    end

    def self._git_complete_remote_branch(cur, prev, subcommand)
      if cur.start_with?('-')
        case subcommand
        when 'fetch'
          opts = %w[-q --quiet -v --verbose --all -a --append --depth= --deepen=
                    --shallow-since= --shallow-exclude= --unshallow --update-shallow
                    --dry-run -f --force -k --keep -p --prune -n --no-tags -t --tags
                    --refmap= -u --update-head-ok --progress --no-progress -j --jobs=
                    --prefetch --set-upstream -o --server-option= --upload-pack]
        when 'pull'
          opts = %w[-q --quiet -v --verbose --rebase -r --no-rebase --ff-only
                    --no-ff --ff --no-commit --commit --no-stat --stat
                    --no-signoff --signoff --no-log --log --squash --no-squash
                    --strategy= -X --strategy-option= --depth= -s --strategy=
                    --allow-unrelated-histories --autostash --no-autostash]
        when 'push'
          opts = %w[-q --quiet -v --verbose --all --mirror --tags --follow-tags
                    -n --dry-run --porcelain --delete --prune -u --set-upstream
                    --thin --no-thin --force -f --force-with-lease --repo
                    --no-verify --progress --signed= --push-option= --atomic
                    -d --delete --receive-pack= --exec= -o --push-option=]
        else
          opts = []
        end
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _git_complete_remotes(cur)
        _git_complete_refs(cur)
      end
    end

    def self._git_complete_log(cur, prev)
      if cur.start_with?('-')
        opts = %w[--follow -p --patch --stat --shortstat --numstat --summary
                  --name-only --name-status --pretty= --format= --abbrev-commit
                  --oneline --graph --decorate --no-decorate --all --branches
                  --remotes --tags --source --merges --no-merges --first-parent
                  --author= --committer= --grep= --all-match --invert-grep
                  --regexp-ignore-case --since= --after= --until= --before=
                  --ancestry-path --cherry-pick --left-right --reverse
                  -n --max-count= --skip= -S -G --pickaxe-regex --walk-reflogs
                  --merge --boundary --simplify-merges --date= --date-order
                  --author-date-order --topo-order --full-history]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _git_complete_refs(cur)
        _git_complete_files(cur)
      end
    end

    def self._git_complete_remote(cur, prev, words, cword, subcommand_idx)
      # Determine remote subcommand
      remote_subcmd = nil
      words[(subcommand_idx + 1)..].each do |word|
        next if word.start_with?('-')
        next if word.empty?  # Skip empty words
        remote_subcmd = word
        break
      end

      if remote_subcmd.nil? || remote_subcmd.empty?
        # Complete remote subcommands
        remote_cmds = %w[add rename remove rm show prune update get-url set-url set-head set-branches]
        @compreply = remote_cmds.select { |c| c.start_with?(cur) }
        return
      end

      case remote_subcmd
      when 'add'
        if cur.start_with?('-')
          opts = %w[-t --track -m --master -f --fetch --tags --no-tags --mirror=]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        end
      when 'rename', 'remove', 'rm', 'show', 'prune', 'get-url', 'set-url', 'set-head', 'set-branches'
        _git_complete_remotes(cur)
      when 'update'
        if cur.start_with?('-')
          @compreply = %w[-p --prune].select { |opt| opt.start_with?(cur) }
        else
          # Complete remote groups or remotes
          _git_complete_remotes(cur)
        end
      end
    end

    def self._git_complete_reset(cur, prev)
      if cur.start_with?('-')
        opts = %w[-q --quiet --soft --mixed --hard --merge --keep -p --patch -N
                  --intent-to-add --pathspec-from-file= --pathspec-file-nul]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _git_complete_refs(cur)
        _git_complete_files(cur)
      end
    end

    def self._git_complete_stash(cur, prev, words, cword, subcommand_idx)
      # Determine stash subcommand
      stash_subcmd = nil
      words[(subcommand_idx + 1)..].each do |word|
        next if word.start_with?('-')
        next if word.empty?  # Skip empty words
        stash_subcmd = word
        break
      end

      if stash_subcmd.nil? || stash_subcmd.empty?
        stash_cmds = %w[list show drop pop apply branch push save clear create store]
        @compreply = stash_cmds.select { |c| c.start_with?(cur) }
        return
      end

      case stash_subcmd
      when 'show', 'drop', 'pop', 'apply', 'branch'
        _git_complete_stash_refs(cur)
      when 'push', 'save'
        if cur.start_with?('-')
          opts = %w[-p --patch -k --keep-index --no-keep-index -q --quiet
                    -u --include-untracked -a --all -m --message --pathspec-from-file=]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_files(cur)
        end
      end
    end

    def self._git_complete_tag(cur, prev)
      case prev
      when '-m', '--message', '-F', '--file'
        @compreply = []  # Message or file
      when '-u', '--local-user'
        @compreply = []  # GPG key
      else
        if cur.start_with?('-')
          opts = %w[-a --annotate -s --sign -u --local-user -f --force -d --delete
                    -v --verify -n --n= -l --list --sort= --contains --no-contains
                    --merged --no-merged --points-at --format= --color --no-color
                    -i --ignore-case -m --message -F --file --cleanup=]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        else
          _git_complete_tags(cur)
        end
      end
    end

    # Helper methods for git completion

    def self._git_complete_refs(cur)
      # Complete git refs (branches, tags, commits)
      @compreply ||= []
      return unless git_repo?

      begin
        # Get all refs
        refs = `git for-each-ref --format='%(refname:short)' 2>/dev/null`.split("\n")
        refs.concat(`git rev-parse --symbolic --branches --tags --remotes 2>/dev/null`.split("\n"))
        refs.uniq!
        @compreply.concat(refs.select { |r| r.start_with?(cur) })
      rescue
        # Git command failed
      end
    end

    def self._git_complete_local_branches(cur)
      @compreply = []
      return unless git_repo?

      begin
        branches = `git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null`.split("\n")
        @compreply = branches.select { |b| b.start_with?(cur) }
      rescue
        # Git command failed
      end
    end

    def self._git_complete_remote_refs(cur)
      @compreply = []
      return unless git_repo?

      begin
        refs = `git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null`.split("\n")
        @compreply = refs.select { |r| r.start_with?(cur) }
      rescue
        # Git command failed
      end
    end

    def self._git_complete_remotes(cur)
      @compreply ||= []
      return unless git_repo?

      begin
        remotes = `git remote 2>/dev/null`.split("\n")
        @compreply.concat(remotes.select { |r| r.start_with?(cur) })
      rescue
        # Git command failed
      end
    end

    def self._git_complete_tags(cur)
      @compreply ||= []
      return unless git_repo?

      begin
        tags = `git tag -l 2>/dev/null`.split("\n")
        @compreply.concat(tags.select { |t| t.start_with?(cur) })
      rescue
        # Git command failed
      end
    end

    def self._git_complete_stash_refs(cur)
      @compreply = []
      return unless git_repo?

      begin
        stashes = `git stash list 2>/dev/null`.each_line.map { |l| l.split(':').first }.compact
        @compreply = stashes.select { |s| s.start_with?(cur) }
      rescue
        # Git command failed
      end
    end

    def self._git_complete_files(cur)
      @compreply ||= []

      # Get modified/untracked files for git commands
      if git_repo?
        begin
          # Modified files
          modified = `git diff --name-only 2>/dev/null`.split("\n")
          # Staged files
          staged = `git diff --cached --name-only 2>/dev/null`.split("\n")
          # Untracked files
          untracked = `git ls-files --others --exclude-standard 2>/dev/null`.split("\n")

          files = (modified + staged + untracked).uniq
          @compreply.concat(files.select { |f| f.start_with?(cur) })
        rescue
          # Git command failed, fall back to regular file completion
        end
      end

      # Also complete regular files
      pattern = cur.empty? ? '*' : "#{cur}*"
      @compreply.concat(Dir.glob(pattern).select { |f| File.file?(f) || File.directory?(f) })
      @compreply.uniq!
    end

    def self.git_repo?
      system('git rev-parse --git-dir >/dev/null 2>&1')
    end

    # ==========================================================================
    # SSH completion function
    # ==========================================================================
    def self._ssh_completion(cmd, cur, prev)
      case prev
      when '-F', '-i', '-S', '-E', '-c', '-o'
        # File/config completions
        if %w[-F -i -S -E].include?(prev)
          run__filedir([])
        else
          @compreply = []
        end
        return
      when '-l'
        # Username completion
        run__usergroup(['-u'])
        return
      when '-p'
        # Port number
        @compreply = []
        return
      when '-J'
        # Jump host - same as hostname
        _ssh_complete_hosts(cur)
        return
      when '-O'
        @compreply = %w[check forward cancel exit stop].select { |opt| opt.start_with?(cur) }
        return
      end

      if cur.start_with?('-')
        opts = %w[-4 -6 -A -a -C -f -G -g -K -k -M -N -n -q -s -T -t -V -v -X -x -Y -y
                  -B -b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _ssh_complete_hosts(cur)
      end
    end

    def self._ssh_complete_hosts(cur)
      @compreply = []
      hosts = Set.new

      # Parse ~/.ssh/config for Host entries
      ssh_config = File.expand_path('~/.ssh/config')
      if File.exist?(ssh_config)
        begin
          File.readlines(ssh_config).each do |line|
            line = line.strip.downcase
            if line.start_with?('host ')
              # Skip patterns with wildcards
              host_entries = line.sub(/^host\s+/, '').split
              host_entries.each do |h|
                hosts << h unless h.include?('*') || h.include?('?')
              end
            end
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      # Parse /etc/hosts
      if File.exist?('/etc/hosts')
        begin
          File.readlines('/etc/hosts').each do |line|
            # Skip comments
            line = line.split('#').first&.strip
            next if line.nil? || line.empty?

            parts = line.split(/\s+/)
            next if parts.length < 2

            # Add hostnames (skip IP address)
            parts[1..].each { |h| hosts << h }
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      # Parse ~/.ssh/known_hosts for hostnames
      known_hosts = File.expand_path('~/.ssh/known_hosts')
      if File.exist?(known_hosts)
        begin
          File.readlines(known_hosts).each do |line|
            next if line.start_with?('#') || line.start_with?('@')

            # First field is hostname/IP (may be hashed)
            host_field = line.split[0]
            next unless host_field

            # Skip hashed entries
            next if host_field.start_with?('|')

            # May have multiple hosts comma-separated, with optional [host]:port
            host_field.split(',').each do |h|
              h = h.sub(/^\[/, '').sub(/\]:\d+$/, '')  # Remove port notation
              hosts << h unless h.match?(/^\d+\.\d+\.\d+\.\d+$/)  # Skip bare IPs
            end
          end
        rescue Errno::EACCES
          # Can't read file
        end
      end

      @compreply = hosts.to_a.select { |h| h.start_with?(cur) }.sort
    end

    # ==========================================================================
    # CD completion function
    # ==========================================================================
    def self._cd_completion(cmd, cur, prev)
      if cur.start_with?('-')
        @compreply = %w[-L -P -e -@].select { |opt| opt.start_with?(cur) }
        return
      end

      # Complete directories only
      run__filedir(['-d'])
    end

    # ==========================================================================
    # Make completion function
    # ==========================================================================
    def self._make_completion(cmd, cur, prev)
      case prev
      when '-f', '--file', '--makefile'
        run__filedir([])
        return
      when '-C', '--directory'
        run__filedir(['-d'])
        return
      when '-I', '--include-dir'
        run__filedir(['-d'])
        return
      when '-j', '--jobs', '-l', '--load-average'
        @compreply = []
        return
      when '-o', '--old-file', '--assume-old', '-W', '--what-if', '--new-file', '--assume-new'
        run__filedir([])
        return
      end

      if cur.start_with?('-')
        opts = %w[-b -B --always-make -C --directory -d --debug -e --environment-overrides
                  -E --eval -f --file --makefile -h --help -i --ignore-errors -I --include-dir
                  -j --jobs -k --keep-going -l --load-average -L --check-symlink-times
                  -n --just-print --dry-run --recon -o --old-file --assume-old -O --output-sync
                  -p --print-data-base -q --question -r --no-builtin-rules -R --no-builtin-variables
                  -s --silent --quiet -S --no-keep-going --stop -t --touch -v --version
                  -w --print-directory --no-print-directory -W --what-if --new-file --assume-new]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
        return
      end

      # Complete make targets
      _make_complete_targets(cur)
    end

    def self._make_complete_targets(cur)
      @compreply = []
      targets = Set.new

      # Find Makefile
      makefiles = %w[GNUmakefile makefile Makefile]
      makefile = makefiles.find { |f| File.exist?(f) }
      return unless makefile

      begin
        File.readlines(makefile).each do |line|
          # Skip comments and empty lines
          next if line.strip.empty? || line.start_with?('#')

          # Match target definitions (target: dependencies)
          # Skip pattern rules (%) and special targets (.)
          if line =~ /^([a-zA-Z0-9_][a-zA-Z0-9_.-]*)\s*:/
            target = $1
            next if target.start_with?('.')  # Skip special targets
            targets << target
          end
        end
      rescue Errno::EACCES, Errno::ENOENT
        # Can't read file
      end

      @compreply = targets.to_a.select { |t| t.start_with?(cur) }.sort
    end

    # ==========================================================================
    # Man completion function
    # ==========================================================================
    def self._man_completion(cmd, cur, prev)
      case prev
      when '-C', '--config-file', '-H', '--html', '-p', '--preprocessor'
        @compreply = []
        return
      when '-M', '--manpath'
        run__filedir(['-d'])
        return
      when '-S', '-s', '--sections'
        @compreply = %w[1 2 3 4 5 6 7 8 9 n l].select { |s| s.start_with?(cur) }
        return
      end

      if cur.start_with?('-')
        opts = %w[-a --all -c --catman -d --debug -D --default -e --extension -f --whatis
                  -h --help -H --html -i --ignore-case -I --match-case -k --apropos
                  -K --global-apropos -l --local-file -L --locale -m --systems
                  -M --manpath -n --nroff -p --preprocessor -P --pager -r --prompt
                  -R --recode -s -S --sections -t --troff -T --troff-device
                  -u --update -V --version -w --where --path --location -W --where-cat
                  -X --gxditview -Z --ditroff]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
        return
      end

      # Complete man page names
      _man_complete_pages(cur)
    end

    def self._man_complete_pages(cur)
      @compreply = []
      pages = Set.new

      # Get MANPATH
      manpath = ENV['MANPATH'] || '/usr/share/man:/usr/local/share/man'
      mandirs = manpath.split(':')

      mandirs.each do |mandir|
        next unless Dir.exist?(mandir)

        # Look in man* subdirectories
        Dir.glob(File.join(mandir, 'man*')).each do |section_dir|
          next unless Dir.exist?(section_dir)

          Dir.entries(section_dir).each do |entry|
            next if entry.start_with?('.')

            # Extract page name (remove .gz, .section)
            name = entry.sub(/\.\d[a-z]*(?:\.gz)?$/, '')
            pages << name if name.start_with?(cur)
          end
        rescue Errno::EACCES
          # Can't read directory
        end
      rescue Errno::EACCES
        # Can't read directory
      end

      @compreply = pages.to_a.sort.first(100)  # Limit results
    end

    # ==========================================================================
    # Kill completion function
    # ==========================================================================
    def self._kill_completion(cmd, cur, prev)
      case prev
      when '-s', '-n', '--signal'
        _kill_complete_signals(cur)
        return
      end

      if cur.start_with?('-')
        if cur.start_with?('--')
          opts = %w[--signal --list --table --help --version]
          @compreply = opts.select { |opt| opt.start_with?(cur) }
        elsif cur == '-'
          # Complete options and signal names
          @compreply = %w[-l -s -n --signal --list --table --help --version]
          # Don't add signal names for just '-' (user hasn't typed a signal yet)
        else
          # Signal names after -
          _kill_complete_signals(cur.sub(/^-/, ''))
          @compreply.map! { |s| "-#{s}" }
        end
        return
      end

      # Complete process IDs and job specs
      _kill_complete_pids(cur)
    end

    def self._kill_complete_signals(cur)
      @compreply = []
      signals = %w[HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1 SEGV USR2 PIPE
                   ALRM TERM STKFLT CHLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ
                   VTALRM PROF WINCH IO PWR SYS]
      @compreply = signals.select { |s| s.start_with?(cur.upcase) }
    end

    def self._kill_complete_pids(cur)
      @compreply = []

      # Complete job specs
      if cur.start_with?('%')
        JobManager.instance.all.each do |job|
          job_spec = "%#{job.id}"
          @compreply << job_spec if job_spec.start_with?(cur)
        end
        return
      end

      # Complete process IDs
      begin
        # Use ps to get running processes
        ps_output = `ps -u #{Process.uid} -o pid,comm 2>/dev/null`
        ps_output.each_line.drop(1).each do |line|
          parts = line.strip.split(/\s+/, 2)
          next if parts.length < 2

          pid = parts[0]
          @compreply << pid if pid.start_with?(cur)
        end
      rescue
        # ps command failed
      end

      @compreply.sort!
    end

    # Valid completion options for compopt
    COMPLETION_OPTIONS = %w[
      bashdefault default dirnames filenames noquote nosort nospace plusdirs
    ].freeze

    def self.run_compopt(args)
      # compopt [-o option] [-DE] [+o option] [name ...]
      # Modify completion options for each name, or for the currently executing completion
      # -o option: Enable option
      # +o option: Disable option
      # -D: Apply to default completion (when no specific completion exists)
      # -E: Apply to empty command completion (when completing on empty line)

      enable_opts = []
      disable_opts = []
      names = []
      apply_default = false
      apply_empty = false

      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-o'
          i += 1
          opt = args[i]
          if opt && COMPLETION_OPTIONS.include?(opt)
            enable_opts << opt
          elsif opt
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when '+o'
          i += 1
          opt = args[i]
          if opt && COMPLETION_OPTIONS.include?(opt)
            disable_opts << opt
          elsif opt
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when '-D'
          apply_default = true
        when '-E'
          apply_empty = true
        when /\A-o(.+)/
          # -oOPTION (combined form)
          opt = $1
          if COMPLETION_OPTIONS.include?(opt)
            enable_opts << opt
          else
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        when /\A\+o(.+)/
          # +oOPTION (combined form)
          opt = $1
          if COMPLETION_OPTIONS.include?(opt)
            disable_opts << opt
          else
            $stderr.puts "compopt: #{opt}: invalid option name"
            return false
          end
        else
          names << arg
        end
        i += 1
      end

      # If no options specified, print current options
      if enable_opts.empty? && disable_opts.empty?
        return print_compopt_options(names, apply_default, apply_empty)
      end

      # Apply options
      if names.empty? && !apply_default && !apply_empty
        # Apply to currently executing completion
        enable_opts.each { |opt| @current_completion_options.add(opt) }
        disable_opts.each { |opt| @current_completion_options.delete(opt) }
      else
        # Apply to named commands
        targets = []
        targets << :default if apply_default
        targets << :empty if apply_empty
        targets.concat(names)

        targets.each do |name|
          @completion_options[name] ||= Set.new
          enable_opts.each { |opt| @completion_options[name].add(opt) }
          disable_opts.each { |opt| @completion_options[name].delete(opt) }
        end
      end

      true
    end

    def self.print_compopt_options(names, apply_default, apply_empty)
      targets = []
      targets << :default if apply_default
      targets << :empty if apply_empty
      targets.concat(names)

      if targets.empty?
        # Print current completion options
        if @current_completion_options.empty?
          puts 'compopt: no options set'
        else
          @current_completion_options.each { |opt| puts "compopt -o #{opt}" }
        end
      else
        targets.each do |name|
          opts = @completion_options[name] || Set.new
          display_name = name.is_a?(Symbol) ? "-#{name.to_s[0].upcase}" : name
          if opts.empty?
            puts "compopt #{display_name}: no options"
          else
            opts.each { |opt| puts "compopt -o #{opt} #{display_name}" }
          end
        end
      end
      true
    end

    def self.get_completion_options(name)
      @completion_options[name] || Set.new
    end

    def self.completion_option?(name, option)
      (@completion_options[name] || Set.new).include?(option)
    end

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

    # =========================================================================
    # Bash-completion helper functions
    # These implement the standard bash-completion helper functions for
    # compatibility with bash-completion scripts.
    # =========================================================================

    # _get_comp_words_by_ref - Get completion words with special word-break handling
    # Options:
    #   -n EXCLUDE  - Characters to exclude from COMP_WORDBREAKS
    #   -c VAR      - Store current word in VAR (default: cur)
    #   -p VAR      - Store previous word in VAR (default: prev)
    #   -w VAR      - Store words array in VAR (default: words)
    #   -i VAR      - Store cword index in VAR (default: cword)
    def self.run__get_comp_words_by_ref(args)
      exclude_chars = ''
      cur_var = 'cur'
      prev_var = 'prev'
      words_var = 'words'
      cword_var = 'cword'

      i = 0
      while i < args.length
        case args[i]
        when '-n'
          i += 1
          exclude_chars = args[i] || ''
        when '-c'
          i += 1
          cur_var = args[i] if args[i]
        when '-p'
          i += 1
          prev_var = args[i] if args[i]
        when '-w'
          i += 1
          words_var = args[i] if args[i]
        when '-i'
          i += 1
          cword_var = args[i] if args[i]
        when 'cur'
          # Legacy positional argument
        when 'prev'
          # Legacy positional argument
        when 'words'
          # Legacy positional argument
        when 'cword'
          # Legacy positional argument
        end
        i += 1
      end

      # Get base completion context
      words = @comp_words.dup
      cword = @comp_cword
      line = @comp_line
      point = @comp_point

      # If excluding characters from wordbreaks, re-split the line
      unless exclude_chars.empty?
        wordbreaks = comp_wordbreaks.chars.reject { |c| exclude_chars.include?(c) }.join
        words, cword = resplit_comp_words(line, point, wordbreaks)
      end

      cur = words[cword] || ''
      prev = cword > 0 ? (words[cword - 1] || '') : ''

      # Set variables via the local scope or environment
      ENV[cur_var] = cur
      ENV[prev_var] = prev
      set_array(words_var, words)
      ENV[cword_var] = cword.to_s

      true
    end

    # Helper to re-split completion words with different wordbreaks
    def self.resplit_comp_words(line, point, wordbreaks)
      words = []
      current = +''
      in_quote = nil
      pos = 0

      line.each_char.with_index do |c, idx|
        if in_quote
          current << c
          in_quote = nil if c == in_quote
        elsif c == '"' || c == "'"
          current << c
          in_quote = c
        elsif c == '\\'
          current << c
          # Skip next char
        elsif wordbreaks.include?(c)
          words << current unless current.empty?
          current = +''
        else
          current << c
        end
      end
      words << current unless current.empty?

      # Calculate cword based on point
      cword = 0
      char_pos = 0
      words.each_with_index do |word, idx|
        word_start = line.index(word, char_pos)
        break unless word_start
        word_end = word_start + word.length
        if point >= word_start && point <= word_end
          cword = idx
          break
        end
        char_pos = word_end
        cword = idx + 1
      end

      [words, [cword, words.length - 1].min]
    end

    # _init_completion - Initialize completion with common setup
    # Options:
    #   -n EXCLUDE  - Characters to exclude from COMP_WORDBREAKS
    #   -s          - Split on = for --option=value
    def self.run__init_completion(args)
      exclude_chars = ''
      split_on_equals = false

      i = 0
      while i < args.length
        case args[i]
        when '-n'
          i += 1
          exclude_chars = args[i] || ''
        when '-s'
          split_on_equals = true
        end
        i += 1
      end

      # Call _get_comp_words_by_ref with the exclude chars
      ref_args = []
      ref_args += ['-n', exclude_chars] unless exclude_chars.empty?
      run__get_comp_words_by_ref(ref_args)

      # Handle --option=value splitting if requested
      if split_on_equals
        cur = ENV['cur'] || ''
        if cur.include?('=')
          # Split on first =
          parts = cur.split('=', 2)
          ENV['cur'] = parts[1] || ''
          ENV['prev'] = parts[0]
        end
      end

      # Set COMPREPLY to empty
      @compreply = []

      true
    end

    # _filedir - Complete filenames, optionally filtering by extension/type
    # Arguments: [extension_pattern]
    # Options:
    #   -d  - Only directories
    def self.run__filedir(args)
      dirs_only = false
      pattern = nil

      args.each do |arg|
        if arg == '-d'
          dirs_only = true
        elsif !arg.start_with?('-')
          pattern = arg
        end
      end

      cur = ENV['cur'] || ''

      # Expand tilde
      expanded_cur = cur.start_with?('~') ? File.expand_path(cur) : cur

      # Get directory and prefix
      if cur.include?('/')
        dir = File.dirname(expanded_cur)
        prefix = File.basename(expanded_cur)
      else
        dir = '.'
        prefix = expanded_cur
      end

      results = []

      begin
        Dir.entries(dir).each do |entry|
          next if entry == '.' || entry == '..'
          next unless entry.start_with?(prefix) || prefix.empty?

          full_path = File.join(dir, entry)

          if dirs_only
            next unless File.directory?(full_path)
          end

          if pattern && !File.directory?(full_path)
            # Check if file matches the pattern
            next unless File.fnmatch(pattern, entry, File::FNM_EXTGLOB)
          end

          # Build the completion string
          if cur.include?('/')
            result = File.join(File.dirname(cur), entry)
          else
            result = entry
          end

          # Add trailing slash for directories
          result += '/' if File.directory?(full_path)

          results << result
        end
      rescue Errno::ENOENT, Errno::EACCES
        # Directory doesn't exist or can't be accessed
      end

      # Add to COMPREPLY
      @compreply = (@compreply || []) + results.sort
      true
    end

    # _have - Check if a command exists in PATH
    def self.run__have(args)
      return false if args.empty?

      cmd = args[0]

      # Check builtins
      return true if builtin?(cmd)

      # Check PATH
      path_dirs = (ENV['PATH'] || '').split(':')
      path_dirs.any? do |dir|
        path = File.join(dir, cmd)
        File.executable?(path) && !File.directory?(path)
      end
    end

    # _split_longopt - Handle --option=value completion
    # Sets prev to option, cur to value after =
    def self.run__split_longopt(args)
      cur = ENV['cur'] || ''

      return false unless cur.include?('=')

      parts = cur.split('=', 2)
      ENV['prev'] = parts[0]
      ENV['cur'] = parts[1] || ''

      # Store for later restoration
      ENV['__SPLIT_LONGOPT_PREV'] = parts[0]
      ENV['__SPLIT_LONGOPT'] = 'set'

      true
    end

    # __ltrim_colon_completions - Remove colon prefix from completions
    # Handles the case where cur contains colons (e.g., package:version)
    def self.run____ltrim_colon_completions(args)
      cur = args[0] || ENV['cur'] || ''

      return true unless cur.include?(':')

      # Find where the colon is and trim completions to match
      colon_pos = cur.rindex(':')
      return true unless colon_pos

      prefix = cur[0..colon_pos]

      # Trim prefix from all completions
      @compreply = (@compreply || []).map do |comp|
        if comp.start_with?(prefix)
          comp[prefix.length..]
        else
          comp
        end
      end

      true
    end

    # _variables - Complete variable names
    def self.run__variables(args)
      cur = ENV['cur'] || ''

      # Remove leading $ if present
      prefix = cur.start_with?('$') ? cur[1..] : cur

      results = []

      # Environment variables
      ENV.keys.each do |key|
        results << "$#{key}" if key.start_with?(prefix)
      end

      # Shell arrays
      @arrays.keys.each do |key|
        results << "$#{key}" if key.start_with?(prefix)
      end

      @compreply = (@compreply || []) + results.sort
      true
    end

    # _tilde - Complete tilde expressions (~username)
    def self.run__tilde(args)
      cur = ENV['cur'] || ''

      return true unless cur.start_with?('~')

      prefix = cur[1..] || ''
      results = []

      # Get usernames from /etc/passwd or similar
      begin
        if File.exist?('/etc/passwd')
          File.readlines('/etc/passwd').each do |line|
            username = line.split(':').first
            next unless username
            results << "~#{username}/" if username.start_with?(prefix)
          end
        end
      rescue Errno::EACCES
        # Can't read passwd file
      end

      # Also try using getent if available
      begin
        `getent passwd 2>/dev/null`.each_line do |line|
          username = line.split(':').first
          next unless username
          results << "~#{username}/" if username.start_with?(prefix)
        end
      rescue
        # getent not available
      end

      @compreply = (@compreply || []) + results.sort.uniq
      true
    end

    # _quote_readline_by_ref - Quote a string for readline
    # Sets the named variable to the quoted string
    def self.run__quote_readline_by_ref(args)
      return false if args.length < 2

      varname = args[0]
      value = args[1]

      # Quote special characters for readline
      quoted = value.gsub(/([\\'"$`\s])/, '\\\\\1')

      ENV[varname] = quoted
      true
    end

    # _parse_help - Parse --help output to extract options
    # Usage: _parse_help command [option]
    def self.run__parse_help(args)
      return false if args.empty?

      cmd = args[0]
      help_opt = args[1] || '--help'

      results = []

      begin
        # Run command with help option and capture output
        output = `#{cmd} #{help_opt} 2>&1`

        # Parse options from the output
        output.each_line do |line|
          # Match patterns like:
          #   -o, --option
          #   --option
          #   -o
          line.scan(/(?:^|\s)(-{1,2}[a-zA-Z0-9][-a-zA-Z0-9_]*)/) do |match|
            opt = match[0]
            results << opt unless results.include?(opt)
          end
        end
      rescue
        # Command failed
      end

      # Filter by current word if set
      cur = ENV['cur'] || ''
      unless cur.empty?
        results = results.select { |opt| opt.start_with?(cur) }
      end

      @compreply = (@compreply || []) + results.sort
      true
    end

    # _upvars - Set variables in caller's scope (simplified implementation)
    # Usage: _upvars [-v varname value]... [-a arrayname values...]...
    def self.run__upvars(args)
      i = 0
      while i < args.length
        case args[i]
        when '-v'
          # Set scalar variable
          varname = args[i + 1]
          value = args[i + 2]
          if varname && value
            ENV[varname] = value
          end
          i += 3
        when '-a'
          # Set array variable: -a N arrayname values...
          count = (args[i + 1] || '0').to_i
          arrayname = args[i + 2]
          if arrayname && count > 0
            values = args[(i + 3)...(i + 3 + count)]
            set_array(arrayname, values)
          end
          i += 3 + count
        else
          i += 1
        end
      end
      true
    end

    # _usergroup - Complete usernames or user:group combinations
    # Options:
    #   -u  - Complete usernames only
    #   -g  - Complete groups only
    def self.run__usergroup(args)
      users_only = args.include?('-u')
      groups_only = args.include?('-g')

      cur = ENV['cur'] || ''
      results = []

      # Check if we're completing group part (after :)
      if cur.include?(':') && !users_only
        prefix = cur.split(':').last || ''
        user_part = cur.split(':').first

        # Complete groups
        begin
          if File.exist?('/etc/group')
            File.readlines('/etc/group').each do |line|
              group = line.split(':').first
              next unless group
              results << "#{user_part}:#{group}" if group.start_with?(prefix)
            end
          end
        rescue Errno::EACCES
        end
      elsif !groups_only
        # Complete users
        begin
          if File.exist?('/etc/passwd')
            File.readlines('/etc/passwd').each do |line|
              username = line.split(':').first
              next unless username
              results << username if username.start_with?(cur)
            end
          end
        rescue Errno::EACCES
        end
      end

      @compreply = (@compreply || []) + results.sort.uniq
      true
    end

    def self.run_bind(args)
      # bind [-m keymap] [-lpsvPSVX]
      # bind [-m keymap] [-q function] [-u function] [-r keyseq]
      # bind [-m keymap] -f filename
      # bind [-m keymap] -x keyseq:shell-command
      # bind [-m keymap] keyseq:function-name
      # bind "set variable value"

      keymap = 'emacs'  # default keymap
      list_functions = false
      print_bindings = false
      print_bindings_readable = false
      print_macros = false
      print_macros_readable = false
      print_variables = false
      print_variables_readable = false
      print_shell_bindings = false
      query_function = nil
      unbind_function = nil
      remove_keyseq = nil
      read_file = nil
      shell_command_binding = nil
      bindings_to_add = []
      variable_settings = []

      i = 0
      while i < args.length
        arg = args[i]

        if arg.start_with?('-') && !arg.include?(':')
          case arg
          when '-m'
            i += 1
            keymap = args[i] if args[i]
          when '-l'
            list_functions = true
          when '-p'
            print_bindings_readable = true
          when '-P'
            print_bindings = true
          when '-s'
            print_macros_readable = true
          when '-S'
            print_macros = true
          when '-v'
            print_variables_readable = true
          when '-V'
            print_variables = true
          when '-X'
            print_shell_bindings = true
          when '-q'
            i += 1
            query_function = args[i]
          when '-u'
            i += 1
            unbind_function = args[i]
          when '-r'
            i += 1
            remove_keyseq = args[i]
          when '-f'
            i += 1
            read_file = args[i]
          when '-x'
            i += 1
            shell_command_binding = args[i]
          else
            # Handle combined flags
            arg[1..].each_char do |c|
              case c
              when 'l' then list_functions = true
              when 'p' then print_bindings_readable = true
              when 'P' then print_bindings = true
              when 's' then print_macros_readable = true
              when 'S' then print_macros = true
              when 'v' then print_variables_readable = true
              when 'V' then print_variables = true
              when 'X' then print_shell_bindings = true
              else
                puts "bind: -#{c}: invalid option"
                return false
              end
            end
          end
        elsif arg.start_with?('set ')
          # Variable setting: set variable value
          variable_settings << arg
        elsif arg.include?(':')
          # keyseq:function-name or keyseq:macro
          bindings_to_add << arg
        else
          puts "bind: #{arg}: invalid key binding"
          return false
        end
        i += 1
      end

      # List all readline function names
      if list_functions
        READLINE_FUNCTIONS.each { |f| puts f }
        return true
      end

      # Print key bindings in reusable format
      if print_bindings_readable
        @key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": #{binding[:value]}"
        end
        return true
      end

      # Print key bindings with function names
      if print_bindings
        @key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "#{escape_keyseq(keyseq)} can be found in #{binding[:value]}."
        end
        return true
      end

      # Print macros in reusable format
      if print_macros_readable
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :macro

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Print macros
      if print_macros
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :macro

          puts "#{escape_keyseq(keyseq)} outputs #{binding[:value]}"
        end
        return true
      end

      # Print readline variables in reusable format
      if print_variables_readable
        READLINE_VARIABLES_LIST.each do |var|
          value = get_readline_variable(var) || 'off'
          puts "set #{var} #{value}"
        end
        return true
      end

      # Print readline variables
      if print_variables
        READLINE_VARIABLES_LIST.each do |var|
          value = get_readline_variable(var) || 'off'
          puts "#{var} is set to `#{value}'"
        end
        return true
      end

      # Print shell command bindings
      if print_shell_bindings
        @key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Query which keys invoke a function
      if query_function
        found = false
        @key_bindings.each do |keyseq, binding|
          if binding[:value] == query_function && binding[:type] == :function
            puts "#{query_function} can be invoked via \"#{escape_keyseq(keyseq)}\"."
            found = true
          end
        end
        puts "#{query_function} is not bound to any keys." unless found
        return true
      end

      # Unbind all keys for a function
      if unbind_function
        @key_bindings.delete_if { |_, binding| binding[:value] == unbind_function }
        return true
      end

      # Remove binding for keyseq
      if remove_keyseq
        @key_bindings.delete(remove_keyseq)
        return true
      end

      # Read bindings from file
      if read_file
        unless File.exist?(read_file)
          puts "bind: #{read_file}: cannot read: No such file or directory"
          return false
        end

        File.readlines(read_file).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          # Skip conditional directives ($if, $else, $endif, $include)
          next if line.start_with?('$')

          if line.start_with?('set ')
            # Variable setting: set variable value
            parts = line.split(/\s+/, 3)
            if parts.length >= 3
              apply_readline_variable(parts[1], parts[2])
            end
          elsif line.include?(':')
            parse_and_add_binding(line, keymap)
          end
        end
        return true
      end

      # Add shell command binding
      if shell_command_binding
        if shell_command_binding.include?(':')
          keyseq, command = shell_command_binding.split(':', 2)
          keyseq = unescape_keyseq(keyseq.delete('"'))
          command = command.delete('"').strip
          @key_bindings[keyseq] = {type: :command, value: command, keymap: keymap}
        else
          puts "bind: #{shell_command_binding}: invalid key binding"
          return false
        end
        return true
      end

      # Add bindings from arguments
      bindings_to_add.each do |binding|
        parse_and_add_binding(binding, keymap)
      end

      # Process variable settings: "set variable value"
      variable_settings.each do |setting|
        parts = setting.split(/\s+/, 3)
        if parts.length >= 3 && parts[0] == 'set'
          apply_readline_variable(parts[1], parts[2])
        end
      end

      true
    end

    def self.parse_and_add_binding(binding_str, keymap = 'emacs')
      keyseq, value = binding_str.split(':', 2)
      return unless keyseq && value

      keyseq = unescape_keyseq(keyseq.delete('"').strip)
      value = value.strip

      # Determine if it's a function or macro
      if value.start_with?('"') && value.end_with?('"')
        # Macro
        @key_bindings[keyseq] = {type: :macro, value: value[1..-2], keymap: keymap}
      else
        # Function
        @key_bindings[keyseq] = {type: :function, value: value, keymap: keymap}
      end
    end

    def self.escape_keyseq(keyseq)
      result = +''
      keyseq.each_char do |c|
        case c.ord
        when 0x00..0x1F
          if c == "\t"
            result << '\\t'
          elsif c == "\n"
            result << '\\n'
          elsif c == "\r"
            result << '\\r'
          elsif c == "\e"
            result << '\\e'
          else
            # Control character: display as \C-x
            result << "\\C-#{(c.ord + 'a'.ord - 1).chr}"
          end
        when 0x7F
          result << '\\C-?'
        when 0x80..0x9F
          # Meta control character
          result << "\\M-\\C-#{(c.ord - 0x80 + 'a'.ord - 1).chr}"
        when 0xA0..0xFF
          # Meta character
          result << "\\M-#{(c.ord - 0x80).chr}"
        else
          result << c
        end
      end
      result
    end

    def self.unescape_keyseq(keyseq)
      result = keyseq.dup

      # Handle meta escape sequences first (\M-x)
      result.gsub!(/\\M-\\C-([a-z@\[\]\\^_?])/) do |_|
        char = ::Regexp.last_match(1)
        if char == '?'
          (0x80 | 0x7F).chr  # Meta-DEL
        else
          (0x80 | (char.ord - 'a'.ord + 1)).chr
        end
      end

      result.gsub!(/\\M-([^\s])/) do |_|
        char = ::Regexp.last_match(1)
        (0x80 | char.ord).chr
      end

      # Handle escape sequences
      result.gsub!('\\e', "\e")
      result.gsub!('\\E', "\e")  # Both \e and \E mean escape
      result.gsub!('\\t', "\t")
      result.gsub!('\\n', "\n")
      result.gsub!('\\r', "\r")
      result.gsub!('\\a', "\a")  # Bell
      result.gsub!('\\b', "\b")  # Backspace
      result.gsub!('\\f', "\f")  # Form feed
      result.gsub!('\\v', "\v")  # Vertical tab
      result.gsub!('\\\\', '\\') # Literal backslash
      result.gsub!('\\"', '"')   # Literal quote
      result.gsub!("\\'", "'")   # Literal single quote

      # Handle octal escape sequences \nnn
      result.gsub!(/\\([0-7]{1,3})/) do |_|
        ::Regexp.last_match(1).to_i(8).chr
      end

      # Handle hex escape sequences \xNN
      result.gsub!(/\\x([0-9a-fA-F]{1,2})/) do |_|
        ::Regexp.last_match(1).to_i(16).chr
      end

      # Handle control characters \C-x format
      result.gsub!(/\\C-([a-zA-Z@\[\]\\^_])/) do |_|
        char = ::Regexp.last_match(1).downcase
        (char.ord - 'a'.ord + 1).chr
      end

      # Handle control characters \C-? format for DEL
      result.gsub!('\\C-?', "\x7F")

      # Handle ^x control character format
      result.gsub!(/\^([a-zA-Z@\[\]\\^_?])/) do |_|
        char = ::Regexp.last_match(1)
        if char == '?'
          "\x7F"  # DEL
        else
          (char.downcase.ord - 'a'.ord + 1).chr
        end
      end

      result
    end

    def self.get_key_binding(keyseq)
      @key_bindings[keyseq]
    end

    def self.clear_key_bindings
      @key_bindings.clear
      @readline_variables.clear
    end

    # Apply a readline variable to Reline (if applicable)
    def self.apply_readline_variable(var, value)
      @readline_variables[var] = value

      # Sync with Reline where possible
      begin
        case var
        when 'editing-mode'
          if value == 'vi'
            Reline.vi_editing_mode if defined?(Reline)
          else
            Reline.emacs_editing_mode if defined?(Reline)
          end
        when 'completion-ignore-case'
          if defined?(Reline)
            Reline.completion_case_fold = (value == 'on')
          end
        when 'horizontal-scroll-mode'
          # Reline doesn't support this, but we store it
        when 'mark-directories'
          # Reline doesn't directly support, but completion can check this
        when 'show-all-if-ambiguous'
          # Could be implemented in completion_proc
        when 'bell-style'
          # Reline doesn't expose bell control
        end
      rescue => e
        $stderr.puts "bind: warning: #{e.message}" if ENV['RUBISH_DEBUG']
      end
    end

    # Get a readline variable value
    def self.get_readline_variable(var)
      # Check Reline state first for live values
      begin
        case var
        when 'editing-mode'
          if defined?(Reline)
            return Reline.vi_editing_mode? ? 'vi' : 'emacs'
          end
        when 'completion-ignore-case'
          if defined?(Reline)
            return Reline.completion_case_fold ? 'on' : 'off'
          end
        end
      rescue
        # Fall through to stored value
      end
      @readline_variables[var]
    end

    def self.run_hash(args)
      # hash [-lr] [-p path] [-dt] [name ...]
      # -r: forget all cached paths
      # -d: forget cached path for each name
      # -l: list in reusable format
      # -p path: cache name with given path
      # -t: print cached path for each name

      if args.empty?
        # List all cached paths
        if @command_hash.empty?
          puts 'hash: hash table empty'
        else
          @command_hash.each do |name, path|
            puts "#{name}=#{path}"
          end
        end
        return true
      end

      # Parse options
      clear_all = false
      delete_mode = false
      list_mode = false
      print_mode = false
      set_path = nil
      names = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-r' && names.empty?
          clear_all = true
          i += 1
        elsif arg == '-d' && names.empty?
          delete_mode = true
          i += 1
        elsif arg == '-l' && names.empty?
          list_mode = true
          i += 1
        elsif arg == '-t' && names.empty?
          print_mode = true
          i += 1
        elsif arg == '-p' && names.empty? && i + 1 < args.length
          set_path = args[i + 1]
          i += 2
        elsif arg.start_with?('-') && names.empty?
          # Handle combined flags
          arg[1..].each_char do |c|
            case c
            when 'r' then clear_all = true
            when 'd' then delete_mode = true
            when 'l' then list_mode = true
            when 't' then print_mode = true
            else
              puts "hash: -#{c}: invalid option"
              return false
            end
          end
          i += 1
        else
          names << arg
          i += 1
        end
      end

      # Handle -r (clear all)
      if clear_all
        @command_hash.clear
        return true
      end

      # Handle -l (list mode) with no names
      if list_mode && names.empty?
        @command_hash.each do |name, path|
          puts "hash -p #{path} #{name}"
        end
        return true
      end

      # Handle names
      all_found = true

      if names.empty? && !set_path
        # No names and no path to set, just list
        if @command_hash.empty?
          puts 'hash: hash table empty'
        else
          @command_hash.each do |name, path|
            puts "#{name}=#{path}"
          end
        end
        return true
      end

      names.each do |name|
        if delete_mode
          # Forget cached path
          if @command_hash.key?(name)
            @command_hash.delete(name)
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        elsif print_mode
          # Print cached path
          if @command_hash.key?(name)
            puts @command_hash[name]
          else
            # Try to find and cache
            path = find_in_path(name)
            if path
              @command_hash[name] = path
              puts path
            else
              puts "hash: #{name}: not found"
              all_found = false
            end
          end
        elsif set_path
          # Set specific path
          @command_hash[name] = set_path
        else
          # Cache the command
          path = find_in_path(name)
          if path
            @command_hash[name] = path
          else
            puts "hash: #{name}: not found"
            all_found = false
          end
        end
      end

      all_found
    end

    def self.hash_lookup(name)
      @command_hash[name]
    end

    def self.hash_store(name, path)
      @command_hash[name] = path
    end

    def self.hash_delete(name)
      @command_hash.delete(name)
    end

    def self.clear_hash
      @command_hash.clear
    end

    def self.run_times(_args)
      # times
      # Display accumulated user and system times for shell and children
      # Format: user system (for shell), then user system (for children)

      t = Process.times

      # Format times as minutes and seconds
      format_time = ->(seconds) {
        mins = (seconds / 60).to_i
        secs = seconds % 60
        format('%dm%0.3fs', mins, secs)
      }

      # Shell times (user and system)
      puts "#{format_time.call(t.utime)} #{format_time.call(t.stime)}"
      # Children times (user and system)
      puts "#{format_time.call(t.cutime)} #{format_time.call(t.cstime)}"

      true
    end

    def self.run_exec(args)
      # exec [-cl] [-a name] [command [arguments]]
      # -c: execute command with empty environment
      # -l: place dash at beginning of argv[0] (login shell)
      # -a name: pass name as argv[0]
      # If no command, exec succeeds but does nothing (useful for redirects)

      # Restricted mode: exec is disabled
      if restricted_mode? && !args.empty?
        $stderr.puts 'rubish: exec: restricted'
        return false
      end

      clear_env = false
      login_shell = false
      argv0 = nil
      cmd_args = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-c' && cmd_args.empty?
          clear_env = true
          i += 1
        elsif arg == '-l' && cmd_args.empty?
          login_shell = true
          i += 1
        elsif arg == '-a' && cmd_args.empty? && i + 1 < args.length
          argv0 = args[i + 1]
          i += 2
        elsif arg == '-cl' || arg == '-lc' && cmd_args.empty?
          clear_env = true
          login_shell = true
          i += 1
        elsif arg.start_with?('-') && cmd_args.empty? && arg.length > 1
          # Handle combined flags like -cla
          arg[1..].each_char do |c|
            case c
            when 'c' then clear_env = true
            when 'l' then login_shell = true
            else
              puts "exec: -#{c}: invalid option"
              return false
            end
          end
          i += 1
        else
          cmd_args = args[i..]
          break
        end
      end

      # If no command, just return success (useful for fd redirects only)
      return true if cmd_args.empty?

      command = cmd_args.first
      command_args = cmd_args[1..] || []

      # Find the command in PATH if not absolute
      unless command.include?('/')
        path = find_in_path(command)
        if path
          command = path
        else
          $stderr.puts "exec: #{cmd_args.first}: not found"
          # execfail: if enabled, don't exit on exec failure
          return false if shopt_enabled?('execfail')
          throw :exit, 127  # Command not found
        end
      end

      # Prepare argv[0]
      if argv0
        exec_argv0 = argv0
      elsif login_shell
        exec_argv0 = "-#{File.basename(command)}"
      else
        exec_argv0 = File.basename(command)
      end

      # Run exit traps before exec
      run_exit_traps

      # Execute
      begin
        if clear_env
          # Clear environment and exec
          exec([command, exec_argv0], *command_args, unsetenv_others: true)
        else
          exec([command, exec_argv0], *command_args)
        end
      rescue Errno::ENOENT
        $stderr.puts "exec: #{cmd_args.first}: not found"
        # execfail: if enabled, don't exit on exec failure
        return false if shopt_enabled?('execfail')
        throw :exit, 127  # Command not found
      rescue Errno::EACCES
        $stderr.puts "exec: #{cmd_args.first}: permission denied"
        # execfail: if enabled, don't exit on exec failure
        return false if shopt_enabled?('execfail')
        throw :exit, 126  # Permission denied
      rescue => e
        $stderr.puts "exec: #{e.message}"
        # execfail: if enabled, don't exit on exec failure
        return false if shopt_enabled?('execfail')
        throw :exit, 126  # General exec failure
      end
    end

    def self.run_umask(args)
      # umask [-p] [-S] [mode]
      # -p: output in a form that can be reused as input
      # -S: output in symbolic form
      # mode: octal or symbolic mode

      symbolic = false
      print_reusable = false
      mode_arg = nil

      args.each do |arg|
        case arg
        when '-S'
          symbolic = true
        when '-p'
          print_reusable = true
        else
          mode_arg = arg
        end
      end

      if mode_arg
        # Set umask
        new_mask = parse_umask(mode_arg)
        if new_mask.nil?
          puts "umask: #{mode_arg}: invalid mode"
          return false
        end
        File.umask(new_mask)
        true
      else
        # Display current umask
        current = File.umask
        if symbolic
          # Symbolic format: u=rwx,g=rx,o=rx
          sym = umask_to_symbolic(current)
          if print_reusable
            puts "umask -S #{sym}"
          else
            puts sym
          end
        else
          # Octal format
          if print_reusable
            puts "umask #{format('%04o', current)}"
          else
            puts format('%04o', current)
          end
        end
        true
      end
    end

    def self.parse_umask(mode)
      if mode =~ /\A[0-7]{1,4}\z/
        # Octal mode
        mode.to_i(8)
      elsif mode =~ /\A[ugoa]*[=+-][rwx]*\z/ || mode.include?(',')
        # Symbolic mode
        parse_symbolic_umask(mode)
      else
        nil
      end
    end

    def self.parse_symbolic_umask(mode)
      current = File.umask
      # Convert umask to permission bits (inverted)
      perms = 0o777 - current

      mode.split(',').each do |clause|
        match = clause.match(/\A([ugoa]*)([-+=])([rwx]*)\z/)
        return nil unless match

        who = match[1]
        op = match[2]
        what = match[3]

        who = 'ugo' if who.empty? || who == 'a'

        # Calculate permission bits
        bits = 0
        bits |= 4 if what.include?('r')
        bits |= 2 if what.include?('w')
        bits |= 1 if what.include?('x')

        who.each_char do |w|
          shift = case w
                  when 'u' then 6
                  when 'g' then 3
                  when 'o' then 0
                  end
          next unless shift

          case op
          when '='
            # Clear and set
            perms &= ~(7 << shift)
            perms |= (bits << shift)
          when '+'
            perms |= (bits << shift)
          when '-'
            perms &= ~(bits << shift)
          end
        end
      end

      # Convert back to umask
      0o777 - perms
    end

    def self.umask_to_symbolic(mask)
      # Convert umask to symbolic format
      perms = 0o777 - mask

      parts = []
      [['u', 6], ['g', 3], ['o', 0]].each do |who, shift|
        bits = (perms >> shift) & 7
        p = +''
        p << 'r' if (bits & 4) != 0
        p << 'w' if (bits & 2) != 0
        p << 'x' if (bits & 1) != 0
        parts << "#{who}=#{p}"
      end

      parts.join(',')
    end

    def self.run_kill(args)
      # kill [-s signal | -signal] pid|%jobspec ...
      # kill -l [signal]
      # Send signals to processes or jobs

      if args.empty?
        puts 'kill: usage: kill [-s signal | -signal] pid|%jobspec ... or kill -l [signal]'
        return false
      end

      # Handle -l (list signals)
      if args.first == '-l'
        if args.length == 1
          # List all signals
          Signal.list.each do |name, num|
            puts "#{num}) SIG#{name}" unless name == 'EXIT'
          end
        else
          # Convert signal number to name or vice versa
          args[1..].each do |arg|
            if arg =~ /\A\d+\z/
              # Number to name
              num = arg.to_i
              name = Signal.list.key(num)
              puts name || num
            else
              # Name to number
              sig_name = arg.upcase.delete_prefix('SIG')
              num = Signal.list[sig_name]
              puts num || arg
            end
          end
        end
        return true
      end

      # Parse signal specification
      signal = 'TERM'  # Default signal
      pids = []
      i = 0

      while i < args.length
        arg = args[i]

        if arg == '-s' && i + 1 < args.length
          # -s SIGNAL
          signal = args[i + 1].upcase.delete_prefix('SIG')
          i += 2
        elsif arg =~ /\A-(\d+)\z/
          # -N (signal number)
          signal = $1.to_i
          i += 1
        elsif arg =~ /\A-([A-Za-z][A-Za-z0-9]*)\z/
          # -SIGNAL (signal name)
          signal = $1.upcase.delete_prefix('SIG')
          i += 1
        else
          pids << arg
          i += 1
        end
      end

      if pids.empty?
        puts 'kill: usage: kill [-s signal | -signal] pid|%jobspec ...'
        return false
      end

      # Normalize signal
      sig = if signal.is_a?(Integer)
              signal
            else
              Signal.list[signal] || Signal.list[signal.delete_prefix('SIG')]
            end

      unless sig
        puts "kill: #{signal}: invalid signal specification"
        return false
      end

      all_success = true
      manager = JobManager.instance

      pids.each do |pid_arg|
        begin
          if pid_arg.start_with?('%')
            # Job spec
            job_id = pid_arg[1..].to_i
            job = manager.get(job_id)
            unless job
              puts "kill: %#{job_id}: no such job"
              all_success = false
              next
            end
            Process.kill(sig, -job.pgid)
          else
            # PID
            pid = pid_arg.to_i
            Process.kill(sig, pid)
          end
        rescue Errno::ESRCH
          puts "kill: (#{pid_arg}) - No such process"
          all_success = false
        rescue Errno::EPERM
          puts "kill: (#{pid_arg}) - Operation not permitted"
          all_success = false
        end
      end

      all_success
    end

    def self.run_wait(args)
      # wait [-fn] [-p VARNAME] [pid|%jobspec ...]
      # Wait for background jobs to complete
      # -n: wait for any single job to complete (bash 4.3+)
      # -p VARNAME: store the PID of the exited process in VARNAME (bash 5.1+)
      # -f: wait for job to terminate, not just change state (bash 5.1+)
      # With no args, waits for all background jobs
      # Returns exit status of last job waited for

      manager = JobManager.instance
      last_status = true
      wait_any = false
      pid_var = nil
      wait_terminate = false
      pids_or_jobs = []

      # Parse options
      i = 0
      while i < args.length
        arg = args[i]

        if arg == '-n'
          wait_any = true
        elsif arg == '-f'
          wait_terminate = true
        elsif arg == '-p'
          i += 1
          if i >= args.length
            puts 'wait: -p: option requires an argument'
            return false
          end
          pid_var = args[i]
        elsif arg.start_with?('-') && arg.length > 1 && !arg.start_with?('-%')
          # Handle combined flags like -fn or -nf
          chars = arg[1..].chars
          j = 0
          while j < chars.length
            c = chars[j]
            case c
            when 'n'
              wait_any = true
            when 'f'
              wait_terminate = true
            when 'p'
              # -p requires argument
              if j + 1 < chars.length
                # Rest of this arg is the varname
                pid_var = chars[j + 1..].join
                break
              elsif i + 1 < args.length
                i += 1
                pid_var = args[i]
              else
                puts 'wait: -p: option requires an argument'
                return false
              end
            else
              puts "wait: -#{c}: invalid option"
              return false
            end
            j += 1
          end
        else
          pids_or_jobs << arg
        end
        i += 1
      end

      # Handle -n: wait for any single job
      if wait_any
        jobs = manager.active
        if jobs.empty? && pids_or_jobs.empty?
          # No jobs to wait for
          return true
        end

        # If specific PIDs/jobs given, wait for one of those
        target_pids = []
        if pids_or_jobs.empty?
          target_pids = jobs.map(&:pid)
        else
          pids_or_jobs.each do |arg|
            if arg.start_with?('%')
              job_id = arg[1..].to_i
              job = manager.get(job_id)
              target_pids << job.pid if job
            else
              target_pids << arg.to_i
            end
          end
        end

        if target_pids.empty?
          return true
        end

        # Wait for any one of the target processes
        begin
          # Use WNOHANG in a loop with sleep to check specific PIDs
          # Or use wait2(-1) if we're waiting for any child
          if pids_or_jobs.empty?
            # Wait for any child
            pid, status = Process.wait2(-1)
          else
            # Poll each target PID
            pid = nil
            status = nil
            loop do
              target_pids.each do |target_pid|
                begin
                  wpid, wstatus = Process.wait2(target_pid, Process::WNOHANG)
                  if wpid
                    pid = wpid
                    status = wstatus
                    break
                  end
                rescue Errno::ECHILD
                  # Process doesn't exist or already reaped
                  target_pids.delete(target_pid)
                end
              end
              break if pid || target_pids.empty?

              sleep 0.01
            end

            unless pid
              return true
            end
          end

          ENV[pid_var] = pid.to_s if pid_var
          job = manager.find_by_pid(pid)
          if job
            manager.update_status(pid, status)
            manager.remove(job.id)
          end
          return status.success?
        rescue Errno::ECHILD
          return true
        end
      end

      # Standard wait behavior
      if pids_or_jobs.empty?
        # Wait for all background jobs
        jobs = manager.active
        if jobs.empty?
          # No tracked jobs, but there may still be child processes
          # (e.g., when monitor mode is off). Wait for all children.
          begin
            loop do
              pid, status = Process.wait2(-1)
              ENV[pid_var] = pid.to_s if pid_var
              last_status = status.success?
            end
          rescue Errno::ECHILD
            # No more children
          end
          return last_status
        end

        jobs.each do |job|
          begin
            pid, status = Process.wait2(job.pid)
            ENV[pid_var] = pid.to_s if pid_var
            manager.update_status(job.pid, status)
            manager.remove(job.id)
            last_status = status.success?
          rescue Errno::ECHILD
            # Process already gone
            manager.remove(job.id)
          end
        end
      else
        # Wait for specific jobs
        pids_or_jobs.each do |arg|
          job = nil

          if arg.start_with?('%')
            # Job spec
            job_id = arg[1..].to_i
            job = manager.get(job_id)
            unless job
              puts "wait: %#{job_id}: no such job"
              last_status = false
              next
            end
          else
            # PID
            pid = arg.to_i
            job = manager.find_by_pid(pid)
            unless job
              # Try waiting for any child with this PID
              begin
                wpid, status = Process.wait2(pid)
                ENV[pid_var] = wpid.to_s if pid_var
                last_status = status.success?
                next
              rescue Errno::ECHILD
                puts "wait: pid #{pid} is not a child of this shell"
                last_status = false
                next
              end
            end
          end

          if job
            begin
              wpid, status = Process.wait2(job.pid)
              ENV[pid_var] = wpid.to_s if pid_var
              manager.update_status(job.pid, status)
              manager.remove(job.id)
              last_status = status.success?
            rescue Errno::ECHILD
              manager.remove(job.id)
            end
          end
        end
      end

      last_status
    end

    def self.run_builtin(args)
      # builtin command [arguments...]
      # Run a shell builtin directly, bypassing functions and aliases
      # Returns error if command is not a builtin

      if args.empty?
        puts 'builtin: usage: builtin command [arguments]'
        return false
      end

      cmd_name = args.first
      cmd_args = args[1..] || []

      unless builtin?(cmd_name)
        puts "builtin: #{cmd_name}: not a shell builtin"
        return false
      end

      run(cmd_name, cmd_args)
    end

    def self.run_command(args)
      # command [-pVv] command [arguments...]
      # -p: use default PATH to search for command
      # -v: print pathname or command type (similar to type -t)
      # -V: print description (similar to type)
      # Without flags: execute command bypassing functions and aliases

      if args.empty?
        puts 'command: usage: command [-pVv] command [arguments]'
        return false
      end

      use_default_path = false
      print_path = false
      print_description = false
      cmd_args = []

      i = 0
      while i < args.length
        arg = args[i]
        if arg.start_with?('-') && arg.length > 1 && cmd_args.empty?
          arg[1..].each_char do |c|
            case c
            when 'p' then use_default_path = true
            when 'v' then print_path = true
            when 'V' then print_description = true
            else
              puts "command: -#{c}: invalid option"
              return false
            end
          end
        else
          cmd_args = args[i..]
          break
        end
        i += 1
      end

      if cmd_args.empty?
        puts 'command: usage: command [-pVv] command [arguments]'
        return false
      end

      cmd_name = cmd_args.first

      # Handle -v flag: print path or type
      if print_path
        if builtin?(cmd_name)
          puts cmd_name
          return true
        end
        path = find_in_path(cmd_name)
        if path
          puts path
          return true
        end
        return false
      end

      # Handle -V flag: print description
      if print_description
        if builtin?(cmd_name)
          puts "#{cmd_name} is a shell builtin"
          return true
        end
        path = find_in_path(cmd_name)
        if path
          puts "#{cmd_name} is #{path}"
          return true
        end
        puts "command: #{cmd_name}: not found"
        return false
      end

      # Execute command bypassing functions and aliases
      if @command_executor
        @command_executor.call(cmd_args)
        true
      else
        # Fallback: just use regular executor with the command
        # This won't bypass functions but at least runs something
        @executor&.call(cmd_args.join(' '))
        true
      end
    end

    def self.run_eval(args)
      # eval [arg ...]
      # Concatenate arguments and execute as a shell command
      return true if args.empty?

      command = args.join(' ')

      unless @executor
        puts 'eval: executor not configured'
        return false
      end

      begin
        @executor.call(command)
        true
      rescue => e
        puts "eval: #{e.message}"
        false
      end
    end

    def self.run_which(args)
      # which [-a] name [name ...]
      # -a: print all matching executables in PATH, not just the first

      if args.empty?
        puts 'which: usage: which [-a] name [name ...]'
        return false
      end

      # Parse options
      show_all = false
      names = []

      args.each do |arg|
        if arg == '-a'
          show_all = true
        else
          names << arg
        end
      end

      if names.empty?
        puts 'which: usage: which [-a] name [name ...]'
        return false
      end

      all_found = true

      names.each do |name|
        if show_all
          paths = find_all_in_path(name)
          if paths.empty?
            puts "#{name} not found"
            all_found = false
          else
            paths.each { |p| puts p }
          end
        else
          path = find_in_path(name)
          if path
            puts path
          else
            puts "#{name} not found"
            all_found = false
          end
        end
      end

      all_found
    end

    def self.run_read(args)
      # Options
      opts = {
        prompt: nil,
        array_name: nil,
        delimiter: "\n",
        use_readline: false,
        initial_text: nil,
        nchars: nil,
        nchars_exact: nil,
        raw: false,
        silent: false,
        timeout: nil,
        fd: nil
      }
      vars = []

      # Parse options
      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-a'
          opts[:array_name] = args[i + 1]
          i += 2
        when '-d'
          delim = args[i + 1]
          opts[:delimiter] = delim&.slice(0, 1) || "\n"
          i += 2
        when '-e'
          opts[:use_readline] = true
          i += 1
        when '-i'
          opts[:initial_text] = args[i + 1]
          i += 2
        when '-n'
          opts[:nchars] = args[i + 1]&.to_i
          i += 2
        when '-N'
          opts[:nchars_exact] = args[i + 1]&.to_i
          i += 2
        when '-p'
          opts[:prompt] = args[i + 1]
          i += 2
        when '-r'
          opts[:raw] = true
          i += 1
        when '-s'
          opts[:silent] = true
          i += 1
        when '-t'
          opts[:timeout] = args[i + 1]&.to_f
          i += 2
        when '-u'
          opts[:fd] = args[i + 1]&.to_i
          i += 2
        else
          vars << arg
          i += 1
        end
      end

      # Default variable is REPLY (unless using array mode)
      vars << 'REPLY' if vars.empty? && opts[:array_name].nil?

      # Read input
      line = read_input_line(opts)
      return false if line.nil?

      # Process backslash escapes unless raw mode
      unless opts[:raw]
        line = process_read_escapes(line)
      end

      # Store in array or variables
      if opts[:array_name]
        store_read_array(opts[:array_name], line)
      elsif opts[:nchars_exact]
        # -N mode: store raw content without splitting
        vars.each { |var| ENV[var] = line }
      else
        store_read_variables(vars, line)
      end

      true
    end

    def self.read_input_line(opts)
      input_stream = opts[:fd] ? IO.new(opts[:fd]) : $stdin

      # Use readline if -e specified
      if opts[:use_readline] && $stdin.tty?
        return read_with_readline(opts)
      end

      # Display prompt
      if opts[:prompt]
        $stderr.print opts[:prompt]
        $stderr.flush
      end

      # Handle silent mode
      if opts[:silent] && $stdin.tty?
        return read_silent(input_stream, opts)
      end

      # Handle timeout (-t option or TMOUT environment variable)
      timeout = opts[:timeout] || tmout
      if timeout && timeout > 0
        opts[:timeout] = timeout
        return read_with_timeout(input_stream, opts)
      end

      # Handle character count modes
      if opts[:nchars_exact]
        return read_exact_chars(input_stream, opts[:nchars_exact])
      elsif opts[:nchars]
        return read_nchars(input_stream, opts[:nchars], opts[:delimiter])
      end

      # Normal line reading with custom delimiter
      read_until_delimiter(input_stream, opts[:delimiter])
    end

    def self.read_with_readline(opts)
      prompt = opts[:prompt] || ''

      if opts[:initial_text]
        # Pre-fill the input buffer
        Reline.pre_input_hook = -> {
          Reline.insert_text(opts[:initial_text])
          Reline.pre_input_hook = nil
        }
      end

      begin
        line = Reline.readline(prompt, false)
        return nil unless line
        line
      rescue Interrupt
        puts
        return nil
      end
    end

    def self.read_silent(input_stream, opts)
      line = +''
      delimiter = opts[:delimiter]
      nchars = opts[:nchars] || opts[:nchars_exact]

      begin
        input_stream.noecho do |io|
          if nchars
            nchars.times do
              char = io.getc
              break unless char
              break if char == delimiter && !opts[:nchars_exact]
              line << char
            end
          else
            loop do
              char = io.getc
              break unless char
              break if char == delimiter
              line << char
            end
          end
        end
        puts if $stdin.tty?  # Print newline after silent input
        line
      rescue Errno::ENOTTY
        # Not a terminal, fall back to normal read
        if nchars
          input_stream.read(nchars)&.chomp(delimiter)
        else
          read_until_delimiter(input_stream, delimiter)
        end
      end
    end

    def self.read_with_timeout(input_stream, opts)
      begin
        Timeout.timeout(opts[:timeout]) do
          if opts[:nchars_exact]
            read_exact_chars(input_stream, opts[:nchars_exact])
          elsif opts[:nchars]
            read_nchars(input_stream, opts[:nchars], opts[:delimiter])
          else
            read_until_delimiter(input_stream, opts[:delimiter])
          end
        end
      rescue Timeout::Error
        nil
      end
    end

    def self.read_exact_chars(input_stream, count)
      # -N: read exactly count chars, ignoring delimiters
      input_stream.read(count)
    end

    def self.read_nchars(input_stream, count, delimiter)
      # -n: read up to count chars or until delimiter
      line = +''
      count.times do
        char = input_stream.getc
        break unless char
        break if char == delimiter
        line << char
      end
      line
    end

    def self.read_until_delimiter(input_stream, delimiter)
      if delimiter == "\n"
        line = input_stream.gets
        return nil unless line
        line.chomp
      else
        line = +''
        loop do
          char = input_stream.getc
          break unless char
          break if char == delimiter
          line << char
        end
        line.empty? && input_stream.eof? ? nil : line
      end
    end

    def self.process_read_escapes(line)
      # Process backslash escapes (line continuation)
      # In read without -r, backslash at end of line continues to next line
      # and backslash before any char removes special meaning
      result = +''
      i = 0
      while i < line.length
        if line[i] == '\\'
          if i + 1 < line.length
            # Backslash escapes next character
            result << line[i + 1]
            i += 2
          else
            # Trailing backslash - in real bash this would continue reading
            # For simplicity, we just skip it
            i += 1
          end
        else
          result << line[i]
          i += 1
        end
      end
      result
    end

    def self.store_read_array(array_name, line)
      # Split line into words using IFS and store as array
      words = split_by_ifs(line)
      clear_read_array(array_name)

      words.each_with_index do |word, idx|
        ENV["#{array_name}_#{idx}"] = word
      end
      ENV["#{array_name}_LENGTH"] = words.length.to_s
    end

    def self.clear_read_array(array_name)
      # Clear existing array elements
      length = ENV["#{array_name}_LENGTH"]&.to_i || 0
      length.times do |i|
        ENV.delete("#{array_name}_#{i}")
      end
      ENV.delete("#{array_name}_LENGTH")
    end

    def self.store_read_variables(vars, line)
      # If only one variable, assign the whole line (with IFS whitespace trimmed)
      if vars.length == 1
        ws_chars = ifs_whitespace
        trimmed = ws_chars.empty? ? line : line.gsub(/\A[#{Regexp.escape(ws_chars)}]+|[#{Regexp.escape(ws_chars)}]+\z/, '')
        ENV[vars[0]] = trimmed
        return
      end

      # Split into at most N parts where N = number of variables
      # This preserves delimiters in the last variable
      words = split_by_ifs_n(line, vars.length)

      vars.each_with_index do |var, idx|
        ENV[var] = words[idx]&.strip || ''
      end
    end

    def self.run_exit(args)
      code = args.first&.to_i || 0

      # Check for active jobs if checkjobs is enabled
      if shopt_enabled?('checkjobs')
        active_jobs = JobManager.instance.active
        if active_jobs.any?
          if @exit_blocked_by_jobs
            # Second exit attempt - proceed with exit
            @exit_blocked_by_jobs = false
          else
            # First exit attempt - warn and block
            @exit_blocked_by_jobs = true
            running = active_jobs.count(&:running?)
            stopped = active_jobs.count(&:stopped?)
            parts = []
            parts << "#{running} running" if running > 0
            parts << "#{stopped} stopped" if stopped > 0
            $stderr.puts "rubish: there are #{parts.join(' and ')} jobs."
            return false
          end
        else
          @exit_blocked_by_jobs = false
        end
      end

      # huponexit: send SIGHUP to all jobs when an interactive login shell exits
      # Note: In bash, this only applies to login shells, but we apply it to interactive shells too
      if shopt_enabled?('huponexit')
        send_hup_to_active_jobs
      end

      run_exit_traps
      throw :exit, code
    end

    # Reset the exit blocked flag (call after any non-exit command)
    def self.clear_exit_blocked
      @exit_blocked_by_jobs = false
    end

    # Send SIGHUP to all active jobs (for huponexit)
    def self.send_hup_to_active_jobs
      active_jobs = JobManager.instance.active
      active_jobs.each do |job|
        begin
          # Send SIGHUP to the process group
          Process.kill('HUP', -job.pgid)
        rescue Errno::ESRCH
          # Process already gone, ignore
        rescue Errno::EPERM
          # Permission denied, try sending to the process directly
          begin
            Process.kill('HUP', job.pid)
          rescue Errno::ESRCH, Errno::EPERM
            # Process gone or no permission, ignore
          end
        end
      end
    end

    def self.run_logout(args)
      # In bash, logout only works in login shells
      # For simplicity, we treat rubish as always being a login shell
      # and logout behaves the same as exit
      unless @shell_options['login_shell']
        # If not a login shell, warn but still exit (bash behavior varies)
        $stderr.puts 'logout: not login shell: use `exit\''
      end
      run_exit(args)
    end

    def self.run_jobs(_args)
      jobs = JobManager.instance.active
      if jobs.empty?
        # No output when no jobs
      else
        jobs.each { |job| puts job }
      end
      true
    end

    def self.run_fg(args)
      unless set_option?('m')
        puts 'fg: no job control'
        return false
      end

      job = find_job(args)
      return false unless job

      puts job.command

      # Bring to foreground
      Process.kill('CONT', -job.pgid) if job.stopped?

      shell_pgid = Process.getpgrp

      # Use 'IGNORE' for SIGTTOU/SIGTTIN so tcsetpgrp works from background
      # Use a noop proc for SIGCHLD because 'IGNORE' causes OS to auto-reap children
      noop = proc {}
      old_chld = trap('CHLD', noop)
      old_ttou = trap('TTOU', 'IGNORE')
      old_ttin = trap('TTIN', 'IGNORE')

      # Give terminal control to the job's process group
      Terminal.set_foreground(job.pgid) if Terminal.tty?

      begin
        # Wait for the job
        _, status = Process.wait2(job.pid, Process::WUNTRACED)
      rescue Errno::ECHILD
        status = nil
      ensure
        # Take back terminal control BEFORE restoring signal handlers
        Terminal.set_foreground(shell_pgid) if Terminal.tty?

        # Restore signal handlers
        trap('CHLD', old_chld || 'DEFAULT')
        trap('TTOU', old_ttou || 'DEFAULT')
        trap('TTIN', old_ttin || 'DEFAULT')
      end

      if status.nil? || !status.stopped?
        job.status = :done
        JobManager.instance.remove(job.id)
      else
        job.status = :stopped
        puts "\n[#{job.id}]  Stopped                 #{job.command}"
      end

      true
    end

    def self.run_bg(args)
      unless set_option?('m')
        puts 'bg: no job control'
        return false
      end

      job = find_job(args)
      return false unless job

      unless job.stopped?
        puts "bg: job #{job.id} is not stopped"
        return false
      end

      job.status = :running
      Process.kill('CONT', -job.pgid)
      puts "[#{job.id}] #{job.command} &"
      true
    end

    def self.find_job(args)
      manager = JobManager.instance

      if args.empty?
        job = manager.last
        unless job
          puts 'fg: no current job'
          return nil
        end
        job
      else
        # Parse %n or just n
        id_str = args.first.to_s.delete_prefix('%')
        id = id_str.to_i
        job = manager.get(id)
        unless job
          puts "fg: %#{id}: no such job"
          return nil
        end
        job
      end
    end

    # Documentation for builtin commands
    BUILTIN_HELP = {
      'cd' => {
        synopsis: 'cd [-L|-P] [dir]',
        description: 'Change the current directory to dir. If dir is not specified, change to $HOME.',
        options: {
          '-L' => 'follow symbolic links (default)',
          '-P' => 'use physical directory structure'
        }
      },
      'exit' => {
        synopsis: 'exit [n]',
        description: 'Exit the shell with a status of n. If n is omitted, exit status is that of the last command executed.'
      },
      'logout' => {
        synopsis: 'logout [n]',
        description: 'Exit a login shell with a status of n. If n is omitted, exit status is that of the last command executed. Prints a warning if not in a login shell.'
      },
      'jobs' => {
        synopsis: 'jobs [-l|-p] [jobspec ...]',
        description: 'List active jobs.',
        options: {
          '-l' => 'list process IDs in addition to normal info',
          '-p' => 'list process IDs only'
        }
      },
      'fg' => {
        synopsis: 'fg [job_spec]',
        description: 'Move job to the foreground. If job_spec is not present, the most recent job is used.'
      },
      'bg' => {
        synopsis: 'bg [job_spec ...]',
        description: 'Move jobs to the background. If job_spec is not present, the most recent job is used.'
      },
      'export' => {
        synopsis: 'export [-n] [name[=value] ...]',
        description: 'Set export attribute for shell variables. Exported variables are passed to child processes.',
        options: {
          '-n' => 'remove the export property from each name',
          '-p' => 'display all exported variables'
        }
      },
      'pwd' => {
        synopsis: 'pwd [-L|-P]',
        description: 'Print the current working directory.',
        options: {
          '-L' => 'print logical path (default)',
          '-P' => 'print physical path (resolve symlinks)'
        }
      },
      'history' => {
        synopsis: 'history [-c] [-d offset] [n]',
        description: 'Display or manipulate the history list.',
        options: {
          '-c' => 'clear the history list',
          '-d offset' => 'delete the history entry at offset',
          'n' => 'list only the last n entries'
        }
      },
      'alias' => {
        synopsis: 'alias [name[=value] ...]',
        description: 'Define or display aliases. Without arguments, print all aliases. With arguments, define aliases.'
      },
      'unalias' => {
        synopsis: 'unalias [-a] name [name ...]',
        description: 'Remove each name from the list of defined aliases.',
        options: {
          '-a' => 'remove all alias definitions'
        }
      },
      'source' => {
        synopsis: 'source filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment.'
      },
      '.' => {
        synopsis: '. filename [arguments]',
        description: 'Read and execute commands from filename in the current shell environment. Same as source.'
      },
      'shift' => {
        synopsis: 'shift [n]',
        description: 'Shift positional parameters to the left by n (default 1).'
      },
      'set' => {
        synopsis: 'set [--] [arg ...]',
        description: 'Set positional parameters, or display shell variables. With -- args, set $1, $2, etc.'
      },
      'return' => {
        synopsis: 'return [n]',
        description: 'Return from a shell function with return value n. If n is omitted, return status is that of the last command.'
      },
      'read' => {
        synopsis: 'read [-a array] [-d delim] [-e] [-i text] [-n nchars] [-N nchars] [-p prompt] [-r] [-s] [-t timeout] [-u fd] [name ...]',
        description: 'Read a line from standard input and split into fields. If no names are supplied, the line is stored in REPLY.',
        options: {
          '-a array' => 'store words in an indexed array (simulated via env vars: ARRAY_0, ARRAY_1, etc.)',
          '-d delim' => 'continue reading until first character of delim is read (instead of newline)',
          '-e' => 'use Readline for input (enables editing, history)',
          '-i text' => 'use text as initial text for Readline (requires -e)',
          '-n nchars' => 'return after reading nchars characters (or delimiter)',
          '-N nchars' => 'return after reading exactly nchars characters (ignores delimiter)',
          '-p prompt' => 'display prompt on stderr before reading',
          '-r' => 'raw mode: do not allow backslash escapes',
          '-s' => 'silent mode: do not echo input (for passwords)',
          '-t timeout' => 'time out and return failure after timeout seconds',
          '-u fd' => 'read from file descriptor fd instead of stdin'
        }
      },
      'echo' => {
        synopsis: 'echo [-n] [-e] [arg ...]',
        description: 'Write arguments to standard output.',
        options: {
          '-n' => 'do not append a newline',
          '-e' => 'enable interpretation of backslash escapes'
        }
      },
      'test' => {
        synopsis: 'test expr',
        description: 'Evaluate conditional expression and return 0 (true) or 1 (false).',
        options: {
          '-b file' => 'true if file is a block special device',
          '-c file' => 'true if file is a character special device',
          '-d file' => 'true if file is a directory',
          '-e file' => 'true if file exists',
          '-f file' => 'true if file is a regular file',
          '-g file' => 'true if file has setgid bit set',
          '-h file' => 'true if file is a symbolic link',
          '-k file' => 'true if file has sticky bit set',
          '-L file' => 'true if file is a symbolic link',
          '-N file' => 'true if file modified since last read',
          '-O file' => 'true if file is owned by effective user ID',
          '-G file' => 'true if file is owned by effective group ID',
          '-p file' => 'true if file is a named pipe (FIFO)',
          '-r file' => 'true if file is readable',
          '-s file' => 'true if file has size greater than zero',
          '-S file' => 'true if file is a socket',
          '-t fd' => 'true if file descriptor is open and refers to a terminal',
          '-u file' => 'true if file has setuid bit set',
          '-w file' => 'true if file is writable',
          '-x file' => 'true if file is executable',
          '-z string' => 'true if string length is zero',
          '-n string' => 'true if string length is non-zero',
          '-v varname' => 'true if shell variable varname is set',
          '-R varname' => 'true if shell variable varname is a nameref',
          's1 = s2' => 'true if strings are equal',
          's1 != s2' => 'true if strings are not equal',
          's1 < s2' => 'true if s1 sorts before s2 lexicographically',
          's1 > s2' => 'true if s1 sorts after s2 lexicographically',
          'n1 -eq n2' => 'true if integers are equal',
          'n1 -ne n2' => 'true if integers are not equal',
          'n1 -lt n2' => 'true if n1 < n2',
          'n1 -le n2' => 'true if n1 <= n2',
          'n1 -gt n2' => 'true if n1 > n2',
          'n1 -ge n2' => 'true if n1 >= n2',
          'f1 -nt f2' => 'true if file f1 is newer than f2',
          'f1 -ot f2' => 'true if file f1 is older than f2',
          'f1 -ef f2' => 'true if f1 and f2 refer to same device and inode',
          'e1 -a e2' => 'true if both e1 and e2 are true',
          'e1 -o e2' => 'true if either e1 or e2 is true',
          '! expr' => 'true if expr is false'
        }
      },
      '[' => {
        synopsis: '[ expr ]',
        description: 'Evaluate conditional expression. Same as test, but requires closing ].'
      },
      'break' => {
        synopsis: 'break [n]',
        description: 'Exit from within a for, while, or until loop. If n is specified, break n levels.'
      },
      'continue' => {
        synopsis: 'continue [n]',
        description: 'Resume the next iteration of the enclosing for, while, or until loop.'
      },
      'pushd' => {
        synopsis: 'pushd [-n] [dir | +N | -N]',
        description: 'Save current directory on stack and change to dir.',
        options: {
          '-n' => 'suppress directory change, only manipulate stack',
          '+N' => 'rotate stack, bringing Nth directory to top',
          '-N' => 'rotate stack, bringing Nth directory from bottom to top'
        }
      },
      'popd' => {
        synopsis: 'popd [-n] [+N | -N]',
        description: 'Remove entries from the directory stack.',
        options: {
          '-n' => 'suppress directory change, only manipulate stack',
          '+N' => 'remove Nth entry from top of stack',
          '-N' => 'remove Nth entry from bottom of stack'
        }
      },
      'dirs' => {
        synopsis: 'dirs [-c] [-l] [-p] [-v]',
        description: 'Display the directory stack.',
        options: {
          '-c' => 'clear the directory stack',
          '-l' => 'use full pathnames (no ~ substitution)',
          '-p' => 'print one entry per line',
          '-v' => 'print with index numbers'
        }
      },
      'trap' => {
        synopsis: 'trap [-lp] [[arg] signal_spec ...]',
        description: 'Set or display signal handlers.',
        options: {
          '-l' => 'list signal names and numbers',
          '-p' => 'display current trap settings'
        }
      },
      'getopts' => {
        synopsis: 'getopts optstring name [args]',
        description: 'Parse positional parameters as options. Sets OPTIND and OPTARG.'
      },
      'local' => {
        synopsis: 'local [-n] [name[=value] ...]',
        description: 'Create local variables within a function. Only valid inside a function.',
        options: {
          '-n' => 'make each name a nameref (reference to another variable)'
        }
      },
      'unset' => {
        synopsis: 'unset [-v] [-f] [name ...]',
        description: 'Unset values and attributes of variables and functions.',
        options: {
          '-v' => 'unset variables (default)',
          '-f' => 'unset functions'
        }
      },
      'readonly' => {
        synopsis: 'readonly [-p] [name[=value] ...]',
        description: 'Mark variables as read-only.',
        options: {
          '-p' => 'display all readonly variables'
        }
      },
      'declare' => {
        synopsis: 'declare [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes.',
        options: {
          '-a' => 'indexed array',
          '-A' => 'associative array',
          '-i' => 'integer attribute',
          '-l' => 'convert value to lowercase',
          '-u' => 'convert value to uppercase',
          '-r' => 'make readonly',
          '-x' => 'export to environment',
          '-p' => 'display attributes and values'
        }
      },
      'typeset' => {
        synopsis: 'typeset [-aAfFgilnprtux] [-p] [name[=value] ...]',
        description: 'Declare variables and give them attributes. Same as declare.'
      },
      'let' => {
        synopsis: 'let arg [arg ...]',
        description: 'Evaluate arithmetic expressions. Each arg is an arithmetic expression.'
      },
      'printf' => {
        synopsis: 'printf [-v var] format [arguments]',
        description: 'Write formatted output. Format specifiers: %s (string), %d (integer), %f (float), %q (shell-quoted), %(fmt)T (time), etc.',
        options: {
          '-v var' => 'assign the output to shell variable var instead of printing to stdout',
          '%q' => 'output the argument as a shell-quoted string, safe for reuse as input',
          '%(fmt)T' => 'output date/time using strftime format fmt; argument is epoch seconds (-1=now, -2=shell start)',
          '%*s' => 'dynamic width from argument (negative width means left-align)',
          '%.*s' => 'dynamic precision from argument',
          '%*.*s' => 'both width and precision from arguments'
        }
      },
      'type' => {
        synopsis: 'type [-t|-p|-a] name [name ...]',
        description: 'Display information about command type.',
        options: {
          '-t' => 'print single word: alias, keyword, function, builtin, or file',
          '-p' => 'print disk file path',
          '-a' => 'print all locations'
        }
      },
      'which' => {
        synopsis: 'which [-a] name [name ...]',
        description: 'Locate a command in PATH.',
        options: {
          '-a' => 'print all matching pathnames'
        }
      },
      'true' => {
        synopsis: 'true',
        description: 'Return a successful result (exit status 0).'
      },
      'false' => {
        synopsis: 'false',
        description: 'Return an unsuccessful result (exit status 1).'
      },
      ':' => {
        synopsis: ':',
        description: 'Null command. Does nothing, returns success.'
      },
      'eval' => {
        synopsis: 'eval [arg ...]',
        description: 'Concatenate arguments and execute as a shell command.'
      },
      'command' => {
        synopsis: 'command [-pVv] command [arg ...]',
        description: 'Execute command bypassing shell functions.',
        options: {
          '-p' => 'use default PATH for command search',
          '-v' => 'print command description',
          '-V' => 'print verbose command description'
        }
      },
      'builtin' => {
        synopsis: 'builtin shell-builtin [arguments]',
        description: 'Execute a shell builtin, bypassing functions and aliases.'
      },
      'wait' => {
        synopsis: 'wait [-fn] [-p VARNAME] [id ...]',
        description: 'Wait for job completion and return exit status.',
        options: {
          '-f' => 'wait for job to terminate, not just change state',
          '-n' => 'wait for any single job to complete',
          '-p VARNAME' => 'store PID of exited process in VARNAME'
        }
      },
      'kill' => {
        synopsis: 'kill [-s sigspec | -n signum | -sigspec] pid | jobspec ...',
        description: 'Send a signal to a job or process.',
        options: {
          '-l' => 'list signal names',
          '-s sigspec' => 'specify signal by name',
          '-n signum' => 'specify signal by number'
        }
      },
      'umask' => {
        synopsis: 'umask [-p] [-S] [mode]',
        description: 'Display or set file mode creation mask.',
        options: {
          '-p' => 'output in form that may be reused as input',
          '-S' => 'use symbolic output (u=rwx,g=rx,o=rx)'
        }
      },
      'exec' => {
        synopsis: 'exec [-cl] [-a name] [command [arguments ...]]',
        description: 'Replace the shell with command. With no command, redirections affect current shell.',
        options: {
          '-c' => 'execute with empty environment',
          '-l' => 'place dash in argv[0] (login shell)',
          '-a name' => 'set argv[0] to name'
        }
      },
      'times' => {
        synopsis: 'times',
        description: 'Print accumulated user and system times for the shell and its children.'
      },
      'hash' => {
        synopsis: 'hash [-lr] [-p filename] [-dt] [name ...]',
        description: 'Remember or report command locations.',
        options: {
          '-r' => 'forget all remembered locations',
          '-l' => 'display in reusable format',
          '-p filename' => 'use filename as location for name',
          '-d' => 'forget remembered location for name',
          '-t' => 'print location for name'
        }
      },
      'disown' => {
        synopsis: 'disown [-h] [-ar] [jobspec ...]',
        description: 'Remove jobs from the job table.',
        options: {
          '-h' => 'mark jobs so they do not receive SIGHUP',
          '-a' => 'remove all jobs',
          '-r' => 'remove only running jobs'
        }
      },
      'ulimit' => {
        synopsis: 'ulimit [-SHa] [-bcdefiklmnpqrstuvxT] [limit]',
        description: 'Control process resource limits.',
        options: {
          '-S' => 'use soft limit',
          '-H' => 'use hard limit',
          '-a' => 'all current limits are reported',
          '-c' => 'core file size',
          '-d' => 'data segment size',
          '-f' => 'file size',
          '-l' => 'locked memory size',
          '-m' => 'resident set size',
          '-n' => 'open file descriptors',
          '-s' => 'stack size',
          '-t' => 'CPU time',
          '-u' => 'user processes',
          '-v' => 'virtual memory'
        }
      },
      'suspend' => {
        synopsis: 'suspend [-f]',
        description: 'Suspend shell execution.',
        options: {
          '-f' => 'force suspend even if this is a login shell'
        }
      },
      'shopt' => {
        synopsis: 'shopt [-pqsu] [-o] [optname ...]',
        description: 'Set and unset shell options.',
        options: {
          '-s' => 'enable (set) each optname',
          '-u' => 'disable (unset) each optname',
          '-p' => 'display in reusable format',
          '-q' => 'quiet mode, return status indicates if set',
          '-o' => 'restrict optnames to those defined for set -o'
        }
      },
      'enable' => {
        synopsis: 'enable [-a] [-dnps] [-f filename] [name ...]',
        description: 'Enable and disable shell builtins.',
        options: {
          '-a' => 'print all builtins with enabled/disabled status',
          '-n' => 'disable builtin names',
          '-p' => 'print enabled builtins',
          '-s' => 'print only special builtins'
        }
      },
      'caller' => {
        synopsis: 'caller [expr]',
        description: 'Return the context of the current subroutine call. With expr, return the nth entry from the call stack.'
      },
      'complete' => {
        synopsis: 'complete [-abcdefgjksuv] [-pr] [-DEI] [-o comp-option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [name ...]',
        description: 'Specify how arguments are to be completed.',
        options: {
          '-p' => 'print completion specifications',
          '-r' => 'remove completion specifications',
          '-f' => 'complete with filenames',
          '-d' => 'complete with directories',
          '-b' => 'complete with builtins',
          '-a' => 'complete with aliases',
          '-v' => 'complete with variables',
          '-W wordlist' => 'split wordlist and complete with results',
          '-F function' => 'call function for completions'
        }
      },
      'compgen' => {
        synopsis: 'compgen [-abcdefgjksuv] [-o option] [-A action] [-G globpat] [-W wordlist] [-F function] [-C command] [-X filterpat] [-P prefix] [-S suffix] [word]',
        description: 'Generate possible completions matching word.',
        options: {
          '-a' => 'aliases',
          '-b' => 'builtins',
          '-c' => 'commands',
          '-d' => 'directories',
          '-e' => 'exported variables',
          '-f' => 'filenames',
          '-g' => 'groups',
          '-j' => 'jobs',
          '-k' => 'shell reserved words',
          '-s' => 'services',
          '-u' => 'users',
          '-v' => 'variables',
          '-A action' => 'use action (alias, arrayvar, binding, builtin, command, directory, disabled, enabled, export, file, function, group, helptopic, hostname, job, keyword, running, service, setopt, shopt, signal, stopped, user, variable)',
          '-C command' => 'execute command and use output as completions',
          '-F function' => 'call function to generate completions',
          '-G globpat' => 'expand glob pattern for completions',
          '-W wordlist' => 'split wordlist and use as completions',
          '-X filterpat' => 'remove completions matching pattern',
          '-P prefix' => 'add prefix to each completion',
          '-S suffix' => 'add suffix to each completion'
        }
      },
      'compopt' => {
        synopsis: 'compopt [-o option] [-DE] [+o option] [name ...]',
        description: 'Modify completion options for the currently executing completion, or for named commands.',
        options: {
          '-o option' => 'enable completion option',
          '+o option' => 'disable completion option',
          '-D' => 'apply to default completion',
          '-E' => 'apply to empty command completion',
          'bashdefault' => 'perform bash default completions if no matches',
          'default' => 'use readline default filename completion',
          'dirnames' => 'perform directory name completion',
          'filenames' => 'tell readline completions are filenames',
          'noquote' => 'do not quote completions',
          'nosort' => 'do not sort completions alphabetically',
          'nospace' => 'do not append space after completion',
          'plusdirs' => 'add directory names to generated matches'
        }
      },
      'bind' => {
        synopsis: 'bind [-m keymap] [-lpsvPSVX] [-f filename] [-q name] [-u name] [-r keyseq] [-x keyseq:shell-command] [keyseq:readline-function or keyseq:"macro"]',
        description: 'Set or display readline key bindings and variables.',
        options: {
          '-l' => 'list readline function names',
          '-p' => 'print key bindings',
          '-P' => 'print key bindings with descriptions',
          '-s' => 'print macro bindings',
          '-S' => 'print macro bindings with descriptions',
          '-v' => 'print readline variables',
          '-V' => 'print readline variables with descriptions',
          '-X' => 'print shell command bindings',
          '-q name' => 'query which keys invoke named function',
          '-u name' => 'unbind all keys bound to named function',
          '-r keyseq' => 'remove binding for keyseq',
          '-f filename' => 'read bindings from filename',
          '-x keyseq:cmd' => 'bind keyseq to shell command',
          '-m keymap' => 'use keymap for subsequent bindings'
        }
      },
      'help' => {
        synopsis: 'help [-dms] [pattern ...]',
        description: 'Display information about builtin commands.',
        options: {
          '-d' => 'output short description for each topic',
          '-m' => 'display in pseudo-manpage format',
          '-s' => 'output only a short usage synopsis'
        }
      },
      'fc' => {
        synopsis: 'fc [-e ename] [-lnr] [first] [last] or fc -s [pat=rep] [command]',
        description: 'Display or edit and re-execute commands from the history list.',
        options: {
          '-e ename' => 'use ename as the editor (default: $FCEDIT or $EDITOR or vi)',
          '-l' => 'list commands instead of editing',
          '-n' => 'suppress line numbers when listing',
          '-r' => 'reverse the order of the commands',
          '-s' => 're-execute command without invoking editor'
        }
      },
      'mapfile' => {
        synopsis: 'mapfile [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable.',
        options: {
          '-d delim' => 'use delim as line delimiter instead of newline',
          '-n count' => 'read at most count lines (0 means all)',
          '-O origin' => 'begin assigning at index origin (default 0)',
          '-s count' => 'skip the first count lines',
          '-t' => 'remove trailing delimiter from each line',
          '-u fd' => 'read from file descriptor fd instead of stdin',
          '-C callback' => 'evaluate callback each time quantum lines are read',
          '-c quantum' => 'specify the number of lines between callback calls (default 5000)'
        }
      },
      'readarray' => {
        synopsis: 'readarray [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]',
        description: 'Read lines from standard input into an indexed array variable. Synonym for mapfile.'
      },
      'basename' => {
        synopsis: 'basename NAME [SUFFIX]',
        description: 'Strip directory and suffix from filenames. Print NAME with any leading directory components removed. If SUFFIX is specified, also remove a trailing SUFFIX.',
        options: {
          '-a, --multiple' => 'support multiple arguments and treat each as a NAME',
          '-s, --suffix=SUFFIX' => 'remove a trailing SUFFIX; implies -a',
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      'dirname' => {
        synopsis: 'dirname NAME...',
        description: 'Strip last component from file name. Output each NAME with its last non-slash component and trailing slashes removed; if NAME contains no slashes, output "." (meaning the current directory).',
        options: {
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      'realpath' => {
        synopsis: 'realpath [OPTION]... FILE...',
        description: 'Print the resolved absolute file name. All but the last component must exist.',
        options: {
          '-e, --canonicalize-existing' => 'all components of the path must exist',
          '-m, --canonicalize-missing' => 'no path components need exist or be a directory',
          '-q, --quiet' => 'suppress most error messages',
          '-s, --strip, --no-symlinks' => 'don\'t expand symlinks',
          '-z, --zero' => 'end each output line with NUL, not newline'
        }
      },
      # Bash-completion helper functions
      '_get_comp_words_by_ref' => {
        synopsis: '_get_comp_words_by_ref [-n EXCLUDE] [-c VAR] [-p VAR] [-w VAR] [-i VAR] [cur] [prev] [words] [cword]',
        description: 'Get completion words from COMP_WORDS with optional word-break exclusion. Sets cur, prev, words array, and cword index variables.',
        options: {
          '-n EXCLUDE' => 'characters to exclude from COMP_WORDBREAKS',
          '-c VAR' => 'store current word in VAR (default: cur)',
          '-p VAR' => 'store previous word in VAR (default: prev)',
          '-w VAR' => 'store words array in VAR (default: words)',
          '-i VAR' => 'store cword index in VAR (default: cword)'
        }
      },
      '_init_completion' => {
        synopsis: '_init_completion [-n EXCLUDE] [-s]',
        description: 'Initialize completion with common setup. Calls _get_comp_words_by_ref and optionally splits --option=value.',
        options: {
          '-n EXCLUDE' => 'characters to exclude from COMP_WORDBREAKS',
          '-s' => 'split on = for --option=value (sets prev to option, cur to value)'
        }
      },
      '_filedir' => {
        synopsis: '_filedir [-d] [PATTERN]',
        description: 'Complete filenames and directories. Adds matching files/directories to COMPREPLY.',
        options: {
          '-d' => 'only complete directories',
          'PATTERN' => 'glob pattern to filter files (directories always included)'
        }
      },
      '_have' => {
        synopsis: '_have COMMAND',
        description: 'Check if a command exists in PATH or is a builtin. Returns true if found, false otherwise.'
      },
      '_split_longopt' => {
        synopsis: '_split_longopt',
        description: 'Handle --option=value completion. If cur contains =, splits it: sets prev to option part, cur to value part.'
      },
      '__ltrim_colon_completions' => {
        synopsis: '__ltrim_colon_completions CUR',
        description: 'Remove colon prefix from COMPREPLY entries. Used when cur contains colons (e.g., package:version).'
      },
      '_variables' => {
        synopsis: '_variables',
        description: 'Complete shell variable names. Adds $VAR entries matching cur to COMPREPLY.'
      },
      '_tilde' => {
        synopsis: '_tilde',
        description: 'Complete tilde expressions (~username). Only operates when cur starts with ~.'
      },
      '_quote_readline_by_ref' => {
        synopsis: '_quote_readline_by_ref VARNAME VALUE',
        description: 'Quote special characters in VALUE for readline and store in VARNAME.'
      },
      '_parse_help' => {
        synopsis: '_parse_help COMMAND [HELP_OPTION]',
        description: 'Parse command --help output to extract options. Adds matching options to COMPREPLY.',
        options: {
          'HELP_OPTION' => 'option to get help (default: --help)'
        }
      },
      '_upvars' => {
        synopsis: '_upvars [-v VAR VALUE]... [-a N ARRAY VALUES...]...',
        description: 'Set variables in caller\'s scope.',
        options: {
          '-v VAR VALUE' => 'set scalar variable VAR to VALUE',
          '-a N ARRAY VALUES' => 'set array variable ARRAY to N VALUES'
        }
      },
      '_usergroup' => {
        synopsis: '_usergroup [-u] [-g]',
        description: 'Complete usernames or user:group combinations.',
        options: {
          '-u' => 'complete usernames only',
          '-g' => 'complete groups only'
        }
      },
      'setopt' => {
        synopsis: 'setopt [option ...]',
        description: 'Enable shell options (zsh-style). Option names are case-insensitive and underscores are ignored. Without arguments, lists all enabled options. Prefix option with "no" to disable (e.g., noautocd).'
      },
      'unsetopt' => {
        synopsis: 'unsetopt [option ...]',
        description: 'Disable shell options (zsh-style). Option names are case-insensitive and underscores are ignored. Without arguments, lists all disabled options. Prefix option with "no" to enable (e.g., noautocd enables autocd).'
      }
    }.freeze

    def self.run_help(args)
      # Parse options
      short_desc = false
      manpage = false
      synopsis_only = false

      while args.first&.start_with?('-')
        opt = args.shift
        case opt
        when '-d'
          short_desc = true
        when '-m'
          manpage = true
        when '-s'
          synopsis_only = true
        else
          puts "help: #{opt}: invalid option"
          puts 'help: usage: help [-dms] [pattern ...]'
          return false
        end
      end

      if args.empty?
        # No pattern: list all builtins with short descriptions
        print_all_builtins(short_desc)
        return true
      end

      found_any = false
      args.each do |pattern|
        # Find matching builtins (exact match first, then glob patterns)
        matches = if COMMANDS.include?(pattern)
                    [pattern]
                  else
                    COMMANDS.select { |cmd| File.fnmatch(pattern, cmd) }
                  end

        if matches.empty?
          puts "help: no help topics match '#{pattern}'."
        else
          matches.each do |cmd|
            found_any = true
            print_help_for(cmd, short_desc: short_desc, manpage: manpage, synopsis_only: synopsis_only)
          end
        end
      end

      found_any
    end

    def self.print_all_builtins(short_desc)
      puts 'Shell builtin commands:'
      puts

      if short_desc
        # Print each builtin with short description
        COMMANDS.sort.each do |cmd|
          info = BUILTIN_HELP[cmd]
          if info
            puts "#{cmd} - #{info[:description].split('.').first}."
          else
            puts cmd
          end
        end
      else
        # Print in columns
        builtins = COMMANDS.sort
        col_width = builtins.map(&:length).max + 2
        cols = 80 / col_width
        cols = 1 if cols < 1

        builtins.each_slice(cols) do |row|
          puts row.map { |b| b.ljust(col_width) }.join
        end
      end
    end

    def self.print_help_for(cmd, short_desc: false, manpage: false, synopsis_only: false)
      info = BUILTIN_HELP[cmd]

      unless info
        puts "#{cmd}: no help available"
        return
      end

      if synopsis_only
        puts "#{cmd}: #{info[:synopsis]}"
        return
      end

      if short_desc
        puts "#{cmd} - #{info[:description].split('.').first}."
        return
      end

      if manpage
        print_manpage_format(cmd, info)
      else
        print_standard_format(cmd, info)
      end
    end

    def self.print_standard_format(cmd, info)
      puts "#{cmd}: #{info[:synopsis]}"
      puts "    #{info[:description]}"

      if info[:options] && !info[:options].empty?
        puts
        puts '    Options:'
        info[:options].each do |opt, desc|
          puts "      #{opt.ljust(16)} #{desc}"
        end
      end
      puts
    end

    def self.print_manpage_format(cmd, info)
      puts 'NAME'
      short_desc = info[:description].split('.').first
      puts "    #{cmd} - #{short_desc.downcase}"
      puts
      puts 'SYNOPSIS'
      puts "    #{info[:synopsis]}"
      puts
      puts 'DESCRIPTION'
      # Wrap description at ~70 chars
      desc_lines = wrap_text(info[:description], 66)
      desc_lines.each { |line| puts "    #{line}" }

      if info[:options] && !info[:options].empty?
        puts
        puts 'OPTIONS'
        info[:options].each do |opt, desc|
          puts "    #{opt}"
          wrapped = wrap_text(desc, 62)
          wrapped.each { |line| puts "        #{line}" }
        end
      end
      puts
    end

    def self.wrap_text(text, width)
      return [text] if text.length <= width

      lines = []
      current = +''
      text.split.each do |word|
        if current.empty?
          current = word
        elsif current.length + word.length + 1 <= width
          current << ' ' << word
        else
          lines << current
          current = word
        end
      end
      lines << current unless current.empty?
      lines
    end

    def self.run_fc(args)
      # Parse options
      list_mode = false
      suppress_numbers = false
      reverse_order = false
      reexecute_mode = false
      editor = nil

      while args.first&.start_with?('-') && args.first != '-' && args.first !~ /\A-\d+\z/
        opt = args.shift
        case opt
        when '-l'
          list_mode = true
        when '-n'
          suppress_numbers = true
        when '-r'
          reverse_order = true
        when '-s'
          reexecute_mode = true
        when '-e'
          editor = args.shift
          unless editor
            puts 'fc: -e: option requires an argument'
            return false
          end
        when /\A-[lnr]+\z/
          # Combined flags like -ln, -lr, -lnr
          opt.chars[1..].each do |c|
            case c
            when 'l' then list_mode = true
            when 'n' then suppress_numbers = true
            when 'r' then reverse_order = true
            end
          end
        else
          puts "fc: #{opt}: invalid option"
          puts 'fc: usage: fc [-e ename] [-lnr] [first] [last] or fc -s [pat=rep] [command]'
          return false
        end
      end

      history = Reline::HISTORY.to_a
      return true if history.empty?

      # Handle -s (re-execute) mode
      if reexecute_mode
        return fc_reexecute(args, history)
      end

      # Parse first and last arguments
      first_arg = args.shift
      last_arg = args.shift

      # Resolve range
      first_idx, last_idx = fc_resolve_range(first_arg, last_arg, history, list_mode)
      return false unless first_idx

      # Get commands in range
      commands = fc_get_range(history, first_idx, last_idx)
      commands.reverse! if reverse_order

      if list_mode
        # List mode: display commands
        fc_list_commands(commands, first_idx, last_idx, reverse_order, suppress_numbers)
        true
      else
        # Edit mode: edit and execute commands
        fc_edit_and_execute(commands, editor)
      end
    end

    def self.fc_reexecute(args, history)
      # fc -s [pat=rep] [command]
      substitution = nil
      command_spec = nil

      args.each do |arg|
        if arg.include?('=') && substitution.nil?
          substitution = arg
        else
          command_spec = arg
        end
      end

      # Find the command to re-execute
      cmd = if command_spec.nil?
              history.last
            elsif command_spec =~ /\A-?\d+\z/
              idx = command_spec.to_i
              if idx < 0
                history[idx]
              else
                history[idx - 1]
              end
            else
              # Find command starting with string
              history.reverse.find { |c| c.start_with?(command_spec) }
            end

      unless cmd
        puts 'fc: no command found'
        return false
      end

      # Apply substitution if specified
      if substitution
        pat, rep = substitution.split('=', 2)
        cmd = cmd.sub(pat, rep || '')
      end

      # Display and execute the command
      puts cmd
      @executor&.call(cmd) if @executor
      true
    end

    def self.fc_resolve_range(first_arg, last_arg, history, list_mode)
      hist_size = history.size

      # Default range for list mode: last 16 commands
      # Default range for edit mode: last command
      if first_arg.nil?
        if list_mode
          first_idx = [hist_size - 16, 0].max
          last_idx = hist_size - 1
        else
          first_idx = hist_size - 1
          last_idx = hist_size - 1
        end
        return [first_idx, last_idx]
      end

      # Parse first argument
      first_idx = fc_parse_history_ref(first_arg, history)
      unless first_idx
        puts "fc: #{first_arg}: history specification out of range"
        return nil
      end

      # Parse last argument (defaults to first in list mode, or first in edit mode)
      if last_arg.nil?
        last_idx = list_mode ? hist_size - 1 : first_idx
      else
        last_idx = fc_parse_history_ref(last_arg, history)
        unless last_idx
          puts "fc: #{last_arg}: history specification out of range"
          return nil
        end
      end

      [first_idx, last_idx]
    end

    def self.fc_parse_history_ref(ref, history)
      hist_size = history.size

      if ref =~ /\A-?\d+\z/
        n = ref.to_i
        if n < 0
          # Negative: relative to end
          idx = hist_size + n
        elsif n == 0
          idx = hist_size - 1
        else
          # Positive: absolute (1-based)
          idx = n - 1
        end
        return nil if idx < 0 || idx >= hist_size
        idx
      else
        # String: find most recent command starting with string
        idx = history.rindex { |cmd| cmd.start_with?(ref) }
        idx
      end
    end

    def self.fc_get_range(history, first_idx, last_idx)
      if first_idx <= last_idx
        (first_idx..last_idx).map { |i| [i + 1, history[i]] }
      else
        (last_idx..first_idx).map { |i| [i + 1, history[i]] }.reverse
      end
    end

    def self.fc_list_commands(commands, first_idx, last_idx, reverse_order, suppress_numbers)
      commands.each do |num, cmd|
        if suppress_numbers
          puts cmd
        else
          puts format('%5d  %s', num, cmd)
        end
      end
    end

    def self.fc_edit_and_execute(commands, editor)
      # Determine editor
      editor ||= ENV['FCEDIT'] || ENV['EDITOR'] || 'vi'

      # Create temp file with commands
      tempfile = Tempfile.new(['fc', '.sh'])
      begin
        commands.each { |_num, cmd| tempfile.puts cmd }
        tempfile.close

        # Open editor
        system(editor, tempfile.path)

        # Read edited commands
        edited = File.read(tempfile.path)

        # Execute each line
        edited.each_line do |line|
          line = line.chomp
          next if line.empty? || line.start_with?('#')
          puts line
          @executor&.call(line) if @executor
        end

        true
      ensure
        tempfile.unlink
      end
    end

    def self.run_mapfile(args)
      # Parse options
      delimiter = "\n"
      max_count = 0  # 0 means unlimited
      origin = 0
      skip_count = 0
      strip_trailing = false
      fd = nil
      callback = nil
      quantum = 5000
      array_name = 'MAPFILE'

      while args.first&.start_with?('-')
        opt = args.shift
        case opt
        when '-d'
          delimiter = args.shift
          unless delimiter
            puts 'mapfile: -d: option requires an argument'
            return false
          end
          # Handle escape sequences
          delimiter = delimiter.gsub('\n', "\n").gsub('\t', "\t").gsub('\0', "\0")
        when '-n'
          count_str = args.shift
          unless count_str
            puts 'mapfile: -n: option requires an argument'
            return false
          end
          max_count = count_str.to_i
        when '-O'
          origin_str = args.shift
          unless origin_str
            puts 'mapfile: -O: option requires an argument'
            return false
          end
          origin = origin_str.to_i
        when '-s'
          skip_str = args.shift
          unless skip_str
            puts 'mapfile: -s: option requires an argument'
            return false
          end
          skip_count = skip_str.to_i
        when '-t'
          strip_trailing = true
        when '-u'
          fd_str = args.shift
          unless fd_str
            puts 'mapfile: -u: option requires an argument'
            return false
          end
          fd = fd_str.to_i
        when '-C'
          callback = args.shift
          unless callback
            puts 'mapfile: -C: option requires an argument'
            return false
          end
        when '-c'
          quantum_str = args.shift
          unless quantum_str
            puts 'mapfile: -c: option requires an argument'
            return false
          end
          quantum = quantum_str.to_i
        else
          puts "mapfile: #{opt}: invalid option"
          puts 'mapfile: usage: mapfile [-d delim] [-n count] [-O origin] [-s count] [-t] [-u fd] [-C callback] [-c quantum] [array]'
          return false
        end
      end

      # Get array name if provided
      array_name = args.shift if args.first

      # Read input
      input = if fd
                begin
                  IO.new(fd).read
                rescue Errno::EBADF
                  puts "mapfile: #{fd}: invalid file descriptor"
                  return false
                end
              else
                $stdin.read
              end

      return true if input.nil? || input.empty?

      # Split into lines using delimiter
      lines = if delimiter == "\n"
                input.lines(chomp: false)
              else
                input.split(delimiter, -1).map { |l| "#{l}#{delimiter}" }
              end

      # Remove the last empty element if input ended with delimiter
      lines.pop if lines.last == delimiter || lines.last&.empty?

      # Skip first N lines
      lines = lines.drop(skip_count) if skip_count > 0

      # Limit to max_count lines
      lines = lines.take(max_count) if max_count > 0

      # Clear existing array elements (from origin onwards)
      ENV.keys.select { |k| k.start_with?("#{array_name}_") }.each do |k|
        idx = k.sub("#{array_name}_", '').to_i
        ENV.delete(k) if idx >= origin
      end

      # Store lines in array
      lines.each_with_index do |line, i|
        # Strip trailing delimiter if -t was used
        line = line.chomp(delimiter) if strip_trailing

        idx = origin + i
        ENV["#{array_name}_#{idx}"] = line

        # Call callback if specified
        if callback && ((i + 1) % quantum == 0)
          @executor&.call("#{callback} #{idx} #{line.inspect}")
        end
      end

      # Set array length marker
      ENV["#{array_name}_LENGTH"] = lines.length.to_s

      true
    end

    # Helper to get mapfile array contents
    def self.get_mapfile_array(name = 'MAPFILE')
      length = ENV["#{name}_LENGTH"]&.to_i || 0
      (0...length).map { |i| ENV["#{name}_#{i}"] }
    end

    # Helper to clear mapfile array
    def self.clear_mapfile_array(name = 'MAPFILE')
      ENV.keys.select { |k| k.start_with?("#{name}_") }.each { |k| ENV.delete(k) }
    end

    def self.run_basename(args)
      # basename NAME [SUFFIX]
      # basename -a [-s SUFFIX] NAME...
      # basename -s SUFFIX NAME...
      # -a: support multiple arguments
      # -s SUFFIX: remove trailing SUFFIX
      # -z: end each line with NUL instead of newline
      suffix = nil
      multiple = false
      null_terminated = false

      while args.first&.start_with?('-')
        break if args.first == '--'
        opt = args.shift
        case opt
        when '-a', '--multiple'
          multiple = true
        when '-s', '--suffix'
          suffix = args.shift
          unless suffix
            $stderr.puts 'basename: option requires an argument -- s'
            return false
          end
          multiple = true  # -s implies -a
        when '-z', '--zero'
          null_terminated = true
        else
          $stderr.puts "basename: invalid option -- '#{opt.sub(/^-+/, '')}'"
          $stderr.puts "Try 'basename --help' for more information."
          return false
        end
      end

      # Consume -- if present
      args.shift if args.first == '--'

      if args.empty?
        $stderr.puts 'basename: missing operand'
        $stderr.puts "Try 'basename --help' for more information."
        return false
      end

      # Traditional basename: basename NAME [SUFFIX]
      if !multiple && args.length == 2 && suffix.nil?
        suffix = args.pop
      end

      terminator = null_terminated ? "\0" : "\n"

      args.each do |name|
        result = File.basename(name)
        # Remove suffix if specified and matches
        if suffix && result.end_with?(suffix) && result != suffix
          result = result[0..-(suffix.length + 1)]
        end
        print "#{result}#{terminator}"
      end

      true
    end

    def self.run_dirname(args)
      # dirname NAME...
      # -z: end each line with NUL instead of newline
      null_terminated = false

      while args.first&.start_with?('-')
        break if args.first == '--'
        opt = args.shift
        case opt
        when '-z', '--zero'
          null_terminated = true
        else
          $stderr.puts "dirname: invalid option -- '#{opt.sub(/^-+/, '')}'"
          $stderr.puts "Try 'dirname --help' for more information."
          return false
        end
      end

      # Consume -- if present
      args.shift if args.first == '--'

      if args.empty?
        $stderr.puts 'dirname: missing operand'
        $stderr.puts "Try 'dirname --help' for more information."
        return false
      end

      terminator = null_terminated ? "\0" : "\n"

      args.each do |name|
        result = File.dirname(name)
        print "#{result}#{terminator}"
      end

      true
    end

    def self.run_realpath(args)
      # realpath [OPTION]... FILE...
      # -e, --canonicalize-existing: all components must exist
      # -m, --canonicalize-missing: no components need exist
      # -q, --quiet: suppress error messages
      # -s, --strip, --no-symlinks: don't expand symlinks
      # -z, --zero: end each line with NUL instead of newline
      canonicalize_mode = :existing  # default: all components must exist
      quiet = false
      no_symlinks = false
      null_terminated = false

      while args.first&.start_with?('-')
        break if args.first == '--'
        opt = args.shift
        case opt
        when '-e', '--canonicalize-existing'
          canonicalize_mode = :existing
        when '-m', '--canonicalize-missing'
          canonicalize_mode = :missing
        when '-q', '--quiet'
          quiet = true
        when '-s', '--strip', '--no-symlinks'
          no_symlinks = true
        when '-z', '--zero'
          null_terminated = true
        else
          $stderr.puts "realpath: invalid option -- '#{opt.sub(/^-+/, '')}'"
          $stderr.puts "Try 'realpath --help' for more information."
          return false
        end
      end

      # Consume -- if present
      args.shift if args.first == '--'

      if args.empty?
        $stderr.puts 'realpath: missing operand'
        $stderr.puts "Try 'realpath --help' for more information."
        return false
      end

      terminator = null_terminated ? "\0" : "\n"
      success = true

      args.each do |name|
        begin
          result = if no_symlinks
                     # Don't resolve symlinks, just normalize path
                     File.expand_path(name)
                   elsif canonicalize_mode == :missing
                     # Allow non-existent components
                     File.expand_path(name)
                   else
                     # Default: resolve symlinks, all must exist
                     File.realpath(name)
                   end
          print "#{result}#{terminator}"
        rescue Errno::ENOENT => e
          unless quiet
            $stderr.puts "realpath: #{name}: No such file or directory"
          end
          success = false
        rescue Errno::EACCES => e
          unless quiet
            $stderr.puts "realpath: #{name}: Permission denied"
          end
          success = false
        rescue => e
          unless quiet
            $stderr.puts "realpath: #{name}: #{e.message}"
          end
          success = false
        end
      end

      success
    end

    def self.detect_heredoc(line)
      # Detect heredoc in a line: <<WORD, <<-WORD, <<'WORD', <<"WORD"
      # Does not match herestrings (<<<)
      # Returns [delimiter, strip_tabs] or nil
      return nil unless line.include?('<<')
      return nil if line.include?('<<<')  # Skip herestrings

      # Match heredoc patterns
      # <<-'DELIM' or <<-"DELIM" or <<-DELIM (strip tabs)
      if line =~ /<<-\s*(['"])([^'"]+)\1/
        return [$2, true]
      elsif line =~ /<<-\s*([a-zA-Z_][a-zA-Z0-9_]*)/
        return [$1, true]
      # <<'DELIM' or <<"DELIM" or <<DELIM (no strip tabs)
      elsif line =~ /<<\s*(['"])([^'"]+)\1/
        return [$2, false]
      elsif line =~ /<<\s*([a-zA-Z_][a-zA-Z0-9_]*)/
        return [$1, false]
      end

      nil
    end
  end
end
