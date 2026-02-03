# frozen_string_literal: true

require_relative '../shell_state'
require_relative '../data/builtin_help'
require_relative '../data/shell_options'
require_relative '../data/readline_config'
require_relative '../data/completion_data'
require_relative '../completions/git'
require_relative '../completions/ssh'
require_relative '../completions/help_parser'
require_relative '../completions/bash_helpers'
require_relative '../builtins/trap'
require_relative '../builtins/echo_printf'
require_relative '../builtins/arithmetic'
require_relative '../builtins/directory_stack'
require_relative '../builtins/read'
require_relative '../builtins/hash_directories'
require_relative '../builtins/bind_readline'

module Rubish
  module Builtins
    COMMANDS = %w(cd exit logout jobs fg bg export pwd history alias unalias source . shift set return read echo test [ break continue pushd popd dirs trap getopts local unset readonly declare typeset let printf type which true false : eval command builtin wait kill umask exec times hash disown ulimit suspend shopt enable caller complete compgen compopt bind bindkey help fc mapfile readarray basename dirname realpath _get_comp_words_by_ref _init_completion _filedir _have _split_longopt __ltrim_colon_completions _variables _tilde _quote_readline_by_ref _parse_help _upvars _usergroup setopt unsetopt autoload compinit compdef __git_ps1 require).freeze

    # Method names for builtin commands (accounting for Ruby keyword conflicts)
    # Note: '.', ':', '[', 'typeset', 'readarray', '__git_ps1', '__ltrim_colon_completions'
    # are mapped via NAME_TO_METHOD to their method names
    BUILTIN_METHODS = Set.new(%i[
      cd exit logout jobs fg bg export pwd history alias unalias source shift set
      return_ read echo test break_ continue pushd popd dirs trap getopts local
      unset readonly declare let printf type which true_ false_ eval command builtin
      wait kill umask exec times hash disown ulimit suspend shopt enable caller
      complete compgen compopt bind bindkey help fc mapfile basename dirname realpath
      _get_comp_words_by_ref _init_completion _filedir _have _split_longopt
      _ltrim_colon_completions _variables _tilde _quote_readline_by_ref _parse_help
      _upvars _usergroup setopt unsetopt autoload compinit compdef git_ps1 require
    ]).freeze

    # Global state (shared across all sessions) - accessed via Builtins.xxx
    @disabled_builtins = Set.new
    @dynamic_commands = []
    @call_stack = []
    @coprocs = {}
    @named_directories = {}
    @builtin_completion_functions = {}
    @current_state = nil

    class << self
      attr_reader :disabled_builtins, :call_stack, :coprocs, :builtin_completion_functions, :named_directories
      attr_accessor :dynamic_commands, :current_state

      # Create a context for class method calls that delegates to instance methods
      def context
        return nil if @current_state.nil?
        @context ||= nil
        if @context.nil? || @context.state != @current_state
          require_relative '../execution_context'
          @context = ExecutionContext.new(@current_state)
        end
        @context
      end

      # Allow REPL to set its context as the shared context
      def context=(ctx)
        @context = ctx
      end

      # Delegate commonly-used methods to the context for backward compatibility
      # These allow code like `Builtins.run(...)` to work
      def method_missing(method_name, *args, **kwargs, &block)
        ctx = context
        if ctx && ctx.respond_to?(method_name)
          if kwargs.empty?
            ctx.send(method_name, *args, &block)
          else
            ctx.send(method_name, *args, **kwargs, &block)
          end
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        ctx = context
        (ctx && ctx.respond_to?(method_name, include_private)) || super
      end
    end

    # Notify the terminal of the current working directory using OSC 7
    # This enables features like "new tab opens in same directory" in terminal emulators
    def notify_terminal_of_cwd
      return unless $stdout.tty?

      hostname = Socket.gethostname rescue 'localhost'
      path = Dir.pwd
      # URI-encode the path (spaces and special chars)
      encoded_path = path.gsub(/[^a-zA-Z0-9\/_.-]/) { |c| '%%%02X' % c.ord }
      # OSC 7: file://hostname/path
      print "\e]7;file://#{hostname}#{encoded_path}\a"
      $stdout.flush
    end

    # Format error message based on gnu_errfmt setting
    # Standard format: "rubish: message"
    # GNU format: "rubish:source:lineno: message"
    def format_error(message, command: nil)
      prefix = if command
                 "rubish: #{command}: "
               else
                 'rubish: '
               end

      if shopt_enabled?('gnu_errfmt')
        source = @state.source_file_getter&.call || 'rubish'
        lineno = @state.lineno_getter&.call || 0
        "#{source}:#{lineno}: #{prefix.sub(/\Arubish: /, '')}#{message}"
      else
        "#{prefix}#{message}"
      end
    end

    # Array variable methods
    def array?(name)
      @state.arrays.key?(name)
    end

    def get_array(name)
      @state.arrays[name] || []
    end

    def set_array(name, values)
      @state.arrays[name] = values.is_a?(Array) ? values : [values]
    end

    def get_array_element(name, index)
      arr = @state.arrays[name]
      return '' unless arr
      arr[index.to_i] || ''
    end

    def set_array_element(name, index, value)
      @state.arrays[name] ||= []
      @state.arrays[name][index.to_i] = value
    end

    def indexed_array?(name)
      @state.arrays.key?(name)
    end

    def array_length(name)
      (@state.arrays[name] || []).length
    end

    def array_append(name, values)
      @state.arrays[name] ||= []
      @state.arrays[name].concat(values.is_a?(Array) ? values : [values])
    end

    def unset_array(name)
      @state.arrays.delete(name)
    end

    def unset_array_element(name, index)
      return unless @state.arrays[name]
      @state.arrays[name][index.to_i] = nil
    end

    # Associative array methods
    def assoc_array?(name)
      @state.assoc_arrays.key?(name)
    end

    def declare_assoc_array(name)
      @state.assoc_arrays[name] ||= {}
    end

    def get_assoc_array(name)
      @state.assoc_arrays[name] || {}
    end

    def set_assoc_array(name, hash)
      @state.assoc_arrays[name] = hash.is_a?(Hash) ? hash : {}
    end

    def get_assoc_element(name, key)
      hash = @state.assoc_arrays[name]
      return '' unless hash
      hash[key] || ''
    end

    def set_assoc_element(name, key, value)
      @state.assoc_arrays[name] ||= {}
      @state.assoc_arrays[name][key] = value
    end

    def assoc_keys(name)
      (@state.assoc_arrays[name] || {}).keys
    end

    def assoc_values(name)
      (@state.assoc_arrays[name] || {}).values
    end

    def assoc_length(name)
      (@state.assoc_arrays[name] || {}).length
    end

    def unset_assoc_array(name)
      @state.assoc_arrays.delete(name)
    end

    def unset_assoc_element(name, key)
      return unless @state.assoc_arrays[name]
      @state.assoc_arrays[name].delete(key)
    end

    # Nameref (reference variable) methods
    def nameref?(name)
      (@state.var_attributes[name] || Set.new).include?(:nameref)
    end

    def resolve_nameref(name, visited = Set.new)
      # Resolve nameref chain, detecting circular references
      return name unless @state.namerefs.key?(name)

      if visited.include?(name)
        $stderr.puts format_error('circular name reference', command: name)
        return nil
      end

      visited << name
      target = @state.namerefs[name]
      resolve_nameref(target, visited)
    end

    def get_nameref_target(name)
      @state.namerefs[name]
    end

    def set_nameref(name, target)
      @state.namerefs[name] = target
      @state.var_attributes[name] ||= Set.new
      @state.var_attributes[name] << :nameref
    end

    def unset_nameref(name)
      @state.namerefs.delete(name)
      @state.var_attributes[name]&.delete(:nameref)
    end

    def get_var_through_nameref(name)
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
          return get_var(target) || ''
        end
      end
      get_var(name) || ''
    end

    def set_var_through_nameref(name, value)
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
          set_var(target, value)
        end
        return true
      end
      set_var(name, value)
      true
    end

    def clear_namerefs
      @state.namerefs.each_key do |name|
        @state.var_attributes[name]&.delete(:nameref)
      end
      @state.namerefs.clear
    end

    # IFS (Internal Field Separator) methods
    DEFAULT_IFS = " \t\n"

    # COMP_WORDBREAKS - characters that separate words for completion
    DEFAULT_COMP_WORDBREAKS = " \t\n\"'><=;|&(:"

    def comp_wordbreaks
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
      # Completion variable accessors - delegate to context
      # Generate getter/setter pairs for completion variables
      {comp_words: [], comp_cword: 0, comp_line: '', comp_point: 0, comp_type: 0, comp_key: 0}.each do |name, default|
        define_method(name) { context&.instance_variable_get(:"@#{name}") || default }
        define_method("#{name}=") { |val| context&.instance_variable_set(:"@#{name}", val) }
      end
      # compreply uses different accessors (get_array/set_array)
      def compreply; context&.get_array('COMPREPLY') || []; end
      def compreply=(val); context&.set_array('COMPREPLY', val); end
    end

    def set_completion_context(line:, point:, words:, cword:, type: 9, key: 9)
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

    def clear_completion_context
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

    # Check if we're currently in a completion context
    # Used to suppress stderr during command substitution in completion functions
    def in_completion_context?
      @comp_words && !@comp_words.empty?
    end

    # TMOUT - timeout for read builtin (in seconds)
    def tmout
      tmout_val = ENV['TMOUT']
      return nil if tmout_val.nil? || tmout_val.empty?
      tmout_val.to_f
    end

    def ifs
      ENV['IFS'] || DEFAULT_IFS
    end

    def ifs_whitespace
      # Returns the whitespace characters in IFS (space, tab, newline)
      current_ifs = ifs
      current_ifs.chars.select { |c| c == ' ' || c == "\t" || c == "\n" }.join
    end

    def ifs_non_whitespace
      # Returns the non-whitespace characters in IFS
      current_ifs = ifs
      current_ifs.chars.reject { |c| c == ' ' || c == "\t" || c == "\n" }.join
    end

    def split_by_ifs(str)
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

    def split_by_ifs_n(str, n)
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

    def join_by_ifs(words)
      # Join words using first character of IFS (for $*)
      current_ifs = ifs
      separator = current_ifs.empty? ? '' : current_ifs[0]
      words.join(separator)
    end

    # Coproc methods
    def coproc?(name)
      Builtins.coprocs.key?(name)
    end

    def get_coproc(name)
      Builtins.coprocs[name]
    end

    def set_coproc(name, pid:, read_fd:, write_fd:, reader:, writer:)
      Builtins.coprocs[name] = {
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

    def remove_coproc(name)
      coproc = Builtins.coprocs.delete(name)
      return unless coproc

      # Close file descriptors
      coproc[:reader]&.close rescue nil
      coproc[:writer]&.close rescue nil
      # Clean up array and PID env var
      unset_array(name)
      ENV.delete("#{name}_PID")
    end

    def coproc_read_fd(name)
      Builtins.coprocs.dig(name, :read_fd)
    end

    def coproc_write_fd(name)
      Builtins.coprocs.dig(name, :write_fd)
    end

    def coproc_pid(name)
      Builtins.coprocs.dig(name, :pid)
    end

    def coproc_reader(name)
      Builtins.coprocs.dig(name, :reader)
    end

    def coproc_writer(name)
      Builtins.coprocs.dig(name, :writer)
    end

    def builtin?(name)
      builtin_exists?(name) && !Builtins.disabled_builtins.include?(name)
    end

    def builtin_exists?(name)
      method_name = NAME_TO_METHOD[name] || name.to_sym
      BUILTIN_METHODS.include?(method_name) || Builtins.dynamic_commands.include?(name)
    end

    def builtin_enabled?(name)
      builtin_exists?(name) && !Builtins.disabled_builtins.include?(name)
    end

    def all_commands
      COMMANDS + Builtins.dynamic_commands
    end

    # Mapping from builtin names to method names for special cases
    # Most builtins use their name directly as the method name
    NAME_TO_METHOD = {
      '.' => :source,
      ':' => :true_,
      '[' => :test,
      'typeset' => :declare,
      'readarray' => :mapfile,
      'return' => :return_,
      'break' => :break_,
      'true' => :true_,
      'false' => :false_,
      '__git_ps1' => :git_ps1,
      '__ltrim_colon_completions' => :_ltrim_colon_completions
    }.freeze

    def run(name, args)
      method_name = NAME_TO_METHOD[name] || name.to_sym

      if respond_to?(method_name, false)
        send(method_name, args)
      elsif Builtins.loaded_builtins.key?(name)
        # Check for dynamically loaded builtins
        callable = Builtins.loaded_builtins[name][:callable]
        if callable.respond_to?(:call)
          callable.call(args)
        else
          false
        end
      else
        false
      end
    end

    def cd(args)
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
      print_dir = false

      # Handle cd - (switch to OLDPWD)
      if dir == '-'
        oldpwd = ENV['OLDPWD']
        if oldpwd.nil? || oldpwd.empty?
          $stderr.puts 'cd: OLDPWD not set'
          return false
        end
        dir = oldpwd
        print_dir = true
      end

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

      # Print directory when found via CDPATH or cd -
      puts ENV['PWD'] if found_via_cdpath || print_dir

      # Notify terminal of new working directory (for "new tab in same dir" feature)
      notify_terminal_of_cwd

      true
    rescue Errno::ENOENT => e
      $stderr.puts "cd: #{e.message}"
      false
    end

    # Correct minor spelling errors in directory path for cdspell
    def correct_directory_spelling(path)
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
    def find_similar_directory(parent, name)
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
    def edit_distance_one?(s1, s2)
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

    def getopts(args)
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
        parse_args = @state.positional_params_getter&.call || []
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

    def reset_getopts
      ENV['OPTIND'] = '1'
      ENV['_OPTPOS'] = '1'
      ENV.delete('OPTARG')
    end

    def local(args)
      # local [-n] var=value or local var
      # -n: create a nameref (reference to another variable)
      # Only valid inside a function (when scope stack is not empty)
      if @state.local_scope_stack.empty?
        $stderr.puts 'local: can only be used in a function'
        return false
      end

      current_scope = @state.local_scope_stack.last
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
              warn_shadow(name) if shopt_enabled?('localvar_warning') && (var_set?(name) || nameref?(name))
              # Store both the original value and nameref state
              current_scope[name] = {
                var_value: var_set?(name) ? get_var(name) : :unset,
                nameref_target: nameref?(name) ? get_nameref_target(name) : nil
              }
            end
            # Set up the nameref
            set_nameref(name, value)
            # Don't set var for nameref - the nameref points to target
          else
            # Save original value if not already in this scope
            unless current_scope.key?(name)
              # Warn if shadowing a variable from outer scope
              warn_shadow(name) if shopt_enabled?('localvar_warning') && var_set?(name)
              current_scope[name] = var_set?(name) ? get_var(name) : :unset
            end
            set_var(name, value)
          end
        else
          # Just declare as local without value
          name = arg
          unless current_scope.key?(name)
            # Warn if shadowing a variable from outer scope
            warn_shadow(name) if shopt_enabled?('localvar_warning') && (var_set?(name) || (nameref_mode && nameref?(name)))
            if nameref_mode
              current_scope[name] = {
                var_value: var_set?(name) ? get_var(name) : :unset,
                nameref_target: nameref?(name) ? get_nameref_target(name) : nil
              }
            else
              current_scope[name] = var_set?(name) ? get_var(name) : :unset
            end
          end

          if nameref_mode
            # Create nameref without target (will be set later via assignment)
            # For now, just mark it as a nameref with nil target
            @state.var_attributes[name] ||= Set.new
            @state.var_attributes[name] << :nameref
          else
            # localvar_inherit: inherit value and attributes from outer scope
            if shopt_enabled?('localvar_inherit')
              # Keep the inherited value (already in shell_vars if it exists)
              # Also inherit variable attributes if present
              # (attributes are already global, so nothing more to do for value)
            else
              # Without localvar_inherit, local var without value creates unset variable
              # This is standard bash behavior
              delete_var(name)
            end
          end
        end
      end

      true
    end

    def push_local_scope
      @state.local_scope_stack.push({})
    end

    def pop_local_scope
      return if @state.local_scope_stack.empty?

      scope = @state.local_scope_stack.pop
      # Restore original values
      scope.each do |name, original_value|
        if original_value.is_a?(Hash)
          # This was a local nameref - restore both var and nameref state
          var_val = original_value[:var_value]
          nameref_target = original_value[:nameref_target]

          # First, remove the current nameref
          unset_nameref(name)

          # Restore original value
          if var_val == :unset
            delete_var(name)
          else
            set_var(name, var_val)
          end

          # Restore original nameref if there was one
          if nameref_target
            set_nameref(name, nameref_target)
          end
        elsif original_value == :unset
          delete_var(name)
        else
          set_var(name, original_value)
        end
      end
    end

    def in_function?
      !@state.local_scope_stack.empty?
    end

    # Set a local variable from a function parameter (for Ruby-style def with named args)
    def set_local_from_param(name, value)
      return unless in_function?

      current_scope = @state.local_scope_stack.last
      unless current_scope.key?(name)
        current_scope[name] = var_set?(name) ? get_var(name) : :unset
      end
      set_var(name, value.to_s)
    end

    def clear_local_scopes
      @state.local_scope_stack.clear
    end

    def warn_shadow(name)
      # Print warning to stderr when local variable shadows outer scope variable
      $stderr.puts "local: warning: #{name}: shadows variable in outer scope"
    end

    def unset(args)
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
          @state.function_remover&.call(name)
        else
          # Check for array element reference: arr[index] or arr[key]
          if name =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[(.+)\]\z/
            var_name = $1
            key = $2

            # Check if readonly
            if readonly?(var_name)
              puts "unset: #{var_name}: readonly variable"
              next
            end

            # Unset the specific array element
            if assoc_array?(var_name)
              # Associative array: delete by key
              unset_assoc_element(var_name, key)
            elsif indexed_array?(var_name)
              # Indexed array: set element to nil (bash behavior - creates sparse array)
              unset_array_element(var_name, key)
            end
            next
          end

          # Check if readonly
          if readonly?(name)
            puts "unset: #{name}: readonly variable"
            next
          end

          # localvar_unset: when unsetting a local variable, remove it from local scope
          # and restore the outer scope's value
          if shopt_enabled?('localvar_unset') && !@state.local_scope_stack.empty?
            current_scope = @state.local_scope_stack.last
            if current_scope.key?(name)
              # Remove from local scope and restore original value
              original_value = current_scope.delete(name)
              if original_value == :unset
                delete_var(name)
              else
                set_var(name, original_value)
              end
              next
            end
          end

          # Special handling for BASH_ARGV0: loses special properties when unset
          if name == 'BASH_ARGV0'
            @state.bash_argv0_unsetter&.call
          end

          # Standard behavior: remove from shell_vars and ENV (if exported)
          delete_var(name)
        end
      end

      true
    end

    def readonly(args)
      # readonly [-p] [name[=value] ...]
      # -p: print all readonly variables in reusable format

      if args.empty? || args == ['-p']
        # List all readonly variables
        @state.readonly_vars.each do |name, _|
          value = get_var(name)
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
          if @state.readonly_vars.key?(name) && ENV[name] != value
            puts "readonly: #{name}: readonly variable"
            next
          end
          ENV[name] = value
          @state.readonly_vars[name] = true
        else
          # Mark existing variable as readonly
          @state.readonly_vars[arg] = true
        end
      end

      true
    end

    def readonly?(name)
      @state.readonly_vars.key?(name)
    end

    def clear_readonly_vars
      @state.readonly_vars.clear
    end

    def exported?(name)
      @state.var_attributes[name]&.include?(:export)
    end

    # Get a shell variable's value
    # Checks shell_vars first (for variables set in this shell),
    # then falls back to ENV (for inherited environment variables)
    def get_var(name)
      if @state.shell_vars.key?(name)
        @state.shell_vars[name]
      else
        ENV[name]
      end
    end

    # Locale variables and POSIX mode variable are automatically exported to ENV
    AUTO_EXPORT_VARS = %w[LANG LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME POSIXLY_CORRECT].freeze

    # Set a shell variable's value
    # If the variable is exported or already exists in ENV (inherited), also updates ENV
    # Locale variables (LANG, LC_*) are automatically exported
    def set_var(name, value)
      @state.shell_vars[name] = value
      # If variable is exported, was inherited from parent env, or is an auto-export variable, also update ENV
      ENV[name] = value if exported?(name) || ENV.key?(name) || AUTO_EXPORT_VARS.include?(name)
    end

    # Delete a shell variable (from both shell_vars and ENV)
    def delete_var(name)
      @state.shell_vars.delete(name)
      ENV.delete(name)
      @state.var_attributes.delete(name)
    end

    # Check if a shell variable is set (in shell_vars or ENV)
    def var_set?(name)
      @state.shell_vars.key?(name) || ENV.key?(name)
    end

    # Clear all shell variables (for testing)
    def clear_shell_vars
      @state.shell_vars.clear
    end

    # Export a variable (add to ENV if it has a value)
    def export_var(name)
      @state.var_attributes[name] ||= Set.new
      @state.var_attributes[name] << :export
      # If variable has a value in shell_vars, copy to ENV
      ENV[name] = @state.shell_vars[name] if @state.shell_vars.key?(name)
    end

    def declare(args)
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
          current_scope = @state.local_scope_stack.last
          unless current_scope.key?(name)
            current_scope[name] = ENV.key?(name) ? ENV[name] : :unset
          end
        end

        # Handle -I: inherit attributes and value from previous scope
        if inherit_mode && in_function?
          # Copy existing attributes if variable exists
          if @state.var_attributes[name]
            add_attrs = add_attrs | @state.var_attributes[name]
          end
          # Inherit value if not specified and variable exists
          if value.nil? && ENV.key?(name)
            value = ENV[name]
          end
        end

        # Initialize attributes set for this variable
        @state.var_attributes[name] ||= Set.new

        # Add new attributes
        add_attrs.each { |attr| @state.var_attributes[name] << attr }

        # Remove attributes (except readonly)
        remove_attrs.each { |attr| @state.var_attributes[name].delete(attr) }

        # Handle nameref attribute
        if add_attrs.include?(:nameref)
          if value
            # Set the nameref to point to the target variable
            @state.namerefs[name] = value
          end
        end

        # Handle removing nameref attribute
        if remove_attrs.include?(:nameref)
          @state.namerefs.delete(name)
        end

        # Handle readonly attribute
        if add_attrs.include?(:readonly)
          @state.readonly_vars[name] = true
        end

        # Handle export attribute
        if add_attrs.include?(:export)
          # Variable is marked for export (already in ENV)
        end

        # Set value if provided (but not for namerefs - value is the target name)
        if value && !nameref_mode
          # Strip quotes from value (like export does)
          value = strip_quotes(value)
          value = apply_attributes(name, value)
          ENV[name] = value
        end
      end

      true
    end

    # Strip surrounding quotes from a value (single or double)
    def strip_quotes(value)
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

    def apply_attributes(name, value)
      attrs = @state.var_attributes[name] || Set.new

      # Apply integer attribute
      if attrs.include?(:integer)
        # Evaluate as arithmetic expression
        begin
          # Simple arithmetic evaluation
          result = Kernel.eval(value.gsub(/[a-zA-Z_][a-zA-Z0-9_]*/) { |var| ENV[var] || '0' })
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

    def set_var_with_attributes(name, value)
      # If it's a nameref, set the target variable instead
      if nameref?(name)
        target = resolve_nameref(name)
        return if target.nil?
        name = target
      end

      # Apply attributes when setting a variable
      if @state.var_attributes[name]
        value = apply_attributes(name, value)
      end
      ENV[name] = value
    end

    def print_declaration(name)
      attrs = @state.var_attributes[name] || Set.new
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
        target = @state.namerefs[name]
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

    def print_all_declarations(filter_attrs)
      # Collect all variables with attributes
      vars_to_print = Set.new

      @state.var_attributes.each_key { |name| vars_to_print << name }
      @state.readonly_vars.each_key { |name| vars_to_print << name }
      @state.namerefs.each_key { |name| vars_to_print << name }

      vars_to_print.each do |name|
        attrs = @state.var_attributes[name] || Set.new
        attrs = attrs.dup
        attrs << :readonly if readonly?(name)
        attrs << :nameref if nameref?(name)

        # Filter by attributes if specified
        if filter_attrs.empty? || filter_attrs.subset?(attrs)
          print_declaration(name)
        end
      end
    end

    def print_functions(names, names_only)
      # Get all functions via callback
      functions = @state.function_lister&.call || {}

      if names.empty?
        # List all functions
        functions.each do |name, info|
          print_function(name, info, names_only)
        end
      else
        # List specific functions
        names.each do |name|
          info = @state.function_getter&.call(name)
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

    def print_function(name, info, names_only)
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

    def get_var_attributes(name)
      @state.var_attributes[name] || Set.new
    end

    def has_attribute?(name, attr)
      (@state.var_attributes[name] || Set.new).include?(attr)
    end

    def mark_exported(name)
      @state.var_attributes[name] ||= Set.new
      @state.var_attributes[name] << :export
    end

    def clear_var_attributes
      @state.var_attributes.clear
    end

    def export(args)
      if args.empty?
        # List all exported variables (from ENV, which contains only exported vars)
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
            # Store in shell_vars and ENV (since we're exporting)
            @state.shell_vars[key] = value
            ENV[key] = value
            # Mark as exported
            @state.var_attributes[key] ||= Set.new
            @state.var_attributes[key] << :export
          else
            # Just export existing variable - copy from shell_vars to ENV if it exists
            export_var(arg)
          end
        end
      end
      true
    end

    def pwd(args)
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
    def record_history_timestamp(index, time = Time.now)
      @state.history_timestamps[index] = time
    end

    # Get timestamp for a history entry
    def get_history_timestamp(index)
      @state.history_timestamps[index]
    end

    # Clear all history timestamps
    def clear_history_timestamps
      @state.history_timestamps.clear
    end

    # Remove timestamp for a specific index and reindex remaining
    def remove_history_timestamp(index)
      @state.history_timestamps.delete(index)
      # Reindex: shift all timestamps after deleted index down by 1
      new_timestamps = {}
      @state.history_timestamps.each do |idx, time|
        if idx > index
          new_timestamps[idx - 1] = time
        else
          new_timestamps[idx] = time
        end
      end
      @state.history_timestamps.clear
      @state.history_timestamps.merge!(new_timestamps)
    end

    def history(args)
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
        @state.last_history_line = 0
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
        @state.history_appender&.call
        return true
      end

      # Handle -n: read new lines from history file
      if read_new
        file = @state.history_file_getter&.call
        return true unless file && File.exist?(file)

        begin
          lines = File.readlines(file, chomp: true)
          # Read lines after what we've already read
          file_last_line = @state.last_history_line
          new_lines = lines[file_last_line..]
          if new_lines && !new_lines.empty?
            new_lines.each { |line| Reline::HISTORY << line }
            @state.last_history_line = lines.size
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
        @state.last_history_line = 0
        @state.history_loader&.call
        return true
      end

      # Handle -w: write history to file
      if write_all
        @state.history_saver&.call
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

    def alias(args)
      if args.empty?
        # List all aliases
        @state.aliases.each { |name, value| puts "alias #{name}='#{value}'" }
      else
        args.each do |arg|
          if arg.include?('=')
            name, value = arg.split('=', 2)
            # Remove surrounding quotes if present
            value = value.sub(/\A(['"])(.*)\1\z/, '\2')
            @state.aliases[name] = value
          else
            # Show specific alias
            if @state.aliases.key?(arg)
              puts "alias #{arg}='#{@state.aliases[arg]}'"
            else
              puts "alias: #{arg}: not found"
            end
          end
        end
      end
      true
    end

    def unalias(args)
      if args.empty?
        puts 'unalias: usage: unalias name [name ...]'
        return false
      end

      args.each do |name|
        if @state.aliases.key?(name)
          @state.aliases.delete(name)
        else
          puts "unalias: #{name}: not found"
        end
      end
      true
    end

    def expand_alias(line)
      return line if line.empty?

      # expand_aliases: when disabled, don't expand aliases
      return line unless shopt_enabled?('expand_aliases')

      # Extract the first word
      first_word = line.split(/\s/, 2).first
      return line unless first_word

      if @state.aliases.key?(first_word)
        rest = line[first_word.length..]
        "#{@state.aliases[first_word]}#{rest}"
      else
        line
      end
    end

    def clear_aliases
      @state.aliases.clear
    end

    def source(args)
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

      unless @state.executor
        puts 'source: executor not configured'
        return false
      end

      # Save and set script name, positional params, and source file
      old_script_name = @state.script_name_getter&.call
      old_positional_params = @state.positional_params_getter&.call
      old_source_file = @state.source_file_getter&.call
      @state.script_name_setter&.call(file)
      @state.positional_params_setter&.call(args[1..] || [])
      # bash_source_fullpath: when enabled, store full path; when disabled, use filename as specified
      source_file_value = shopt_enabled?('bash_source_fullpath') ? file : original_file
      @state.source_file_setter&.call(source_file_value)

      # Disable history expansion while sourcing (bash behavior)
      old_sourcing = @state.sourcing_file
      @state.sourcing_file = true

      return_code = catch(:return) do
        buffer = +''
        depth = 0
        pending_function_def = false  # Track if we're waiting for { after ()
        # Track open control structures for better error messages: [[keyword, line_number], ...]
        open_structures = []
        buffer_start_line = 0
        lines = File.readlines(file, chomp: true)
        i = 0

        while i < lines.length
          line = lines[i].strip
          line_number = i + 1  # 1-based line number for error messages
          i += 1
          next if line.empty? || line.start_with?('#')

          # Track where buffer starts for error messages
          buffer_start_line = line_number if buffer.empty?

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
            @state.heredoc_content_setter&.call(content)
          end

          # Remember if we're waiting for function body BEFORE processing this line
          was_pending_function = pending_function_def

          # Track control structure depth
          # Extract keywords while respecting quotes (don't count { } inside quotes)
          keywords = extract_unquoted_keywords(line)
          keywords.each do |word|
            case word
            when 'if', 'unless', 'while', 'until', 'for', 'case', 'def'
              depth += 1
              open_structures << [word, line_number]
            when 'fi', 'done', 'esac', 'end'
              depth -= 1
              open_structures.pop if open_structures.any?
            when '{'
              # If pending function def, don't double-count the depth
              if pending_function_def
                pending_function_def = false
              else
                depth += 1
                open_structures << ['{', line_number]
              end
            when '}'
              depth -= 1
              open_structures.pop if open_structures.any?
            end
          end

          # Track subshell depth separately (only standalone ( at start of word)
          # This handles: ( cmd ) but not: arr=( ... ) or $( ... )
          if line =~ /\A\s*\(/
            depth += 1
            open_structures << ['(', line_number]
          end
          # Check if line is just ) or ends with ) not preceded by ( on same line
          if line =~ /\A\s*\)\s*\z/
            depth -= 1
            open_structures.pop if open_structures.any?
          end

          # Detect function definition: name() or "function name"
          # These need { on next line, so set flag and increment depth
          # But NOT array assignment like VAR=() which has = before ()
          # Also handle name() { on same line - don't set pending, just track the {
          if (line =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*$/ && !line.include?('=')) ||
             (line =~ /\Afunction\s+\w+\s*$/)
            pending_function_def = true
            depth += 1
            open_structures << ['function', line_number]
          end

          # Accumulate lines - use newline for function definitions or multi-line strings, semicolon otherwise
          if buffer.empty?
            buffer = line
          elsif was_pending_function || has_unclosed_quotes(buffer)
            # Function definitions need newline between () and {
            # Multi-line strings need actual newlines preserved
            buffer = "#{buffer}\n#{line}"
          else
            # Other statements can be joined with semicolon
            buffer = "#{buffer}; #{line}"
          end

          # Execute when we have a complete statement
          # A statement is complete when:
          # - depth is 0 (no unclosed control structures)
          # - not waiting for function body
          # - no unclosed quotes in the buffer
          if depth == 0 && !pending_function_def && !has_unclosed_quotes(buffer)
            begin
              execute_sourced_command(buffer, file, buffer_start_line)
            rescue SyntaxError => e
              puts "source: #{file}:#{buffer_start_line}: syntax error: #{e.message}"
            end
            buffer = +''
          end
        end

        # Execute any remaining buffer (incomplete statement)
        unless buffer.empty?
          # If depth > 0, we have unclosed structures - report them
          if depth > 0 && open_structures.any?
            $stderr.puts "source: #{file}: warning: unclosed control structure(s):"
            open_structures.each do |keyword, line_num|
              closing = case keyword
                        when 'if', 'unless' then 'end (or fi)'
                        when 'while', 'until', 'for' then 'end (or done)'
                        when 'case' then 'end (or esac)'
                        when 'def', 'function' then 'end'
                        when '{' then '}'
                        when '(' then ')'
                        else 'end'
                        end
              $stderr.puts "  '#{keyword}' opened at line #{line_num} - expected #{closing}"
            end
          end

          # Check for unclosed quotes
          if has_unclosed_quotes(buffer)
            $stderr.puts "source: #{file}: warning: unclosed quote starting at line #{buffer_start_line}"
          end

          begin
            execute_sourced_command(buffer, file, buffer_start_line)
          rescue SyntaxError => e
            puts "source: #{file}: syntax error (starting at line #{buffer_start_line}): #{e.message}"
          end
        end

        nil
      end

      # Restore script name, positional params, source file, and sourcing flag
      @state.script_name_setter&.call(old_script_name) if old_script_name
      @state.positional_params_setter&.call(old_positional_params) if old_positional_params
      @state.source_file_setter&.call(old_source_file) if old_source_file
      @state.sourcing_file = old_sourcing

      return_code.nil? || return_code == 0
    end

    # Execute a command from a sourced file, with optional profiling
    def execute_sourced_command(buffer, file, line_number)
      if defined?(Rubish::StartupProfiler) && Rubish::StartupProfiler.enabled
        # Truncate long commands for display, show file:line prefix
        display_cmd = buffer.gsub(/\s+/, ' ').strip
        display_cmd = "#{display_cmd[0, 50]}..." if display_cmd.length > 53
        Rubish::StartupProfiler.measure("  #{File.basename(file)}:#{line_number}: #{display_cmd}") do
          @state.executor.call(buffer)
        end
      else
        @state.executor.call(buffer)
      end
    end

    def shift(args)
      n = args.first&.to_i || 1

      return false if n < 0

      params = @state.positional_params_getter&.call || []

      if n > params.length
        # shift_verbose: print error if shift count exceeds positional parameters
        if shopt_enabled?('shift_verbose')
          $stderr.puts format_error('shift count out of range', command: 'shift')
        end
        return false
      end

      @state.positional_params_setter&.call(params.drop(n))
      true
    end

    def set_option?(flag)
      @state.set_options[flag] || false
    end

    # Check if shell is in restricted mode
    def restricted_mode?
      @state.set_options['r'] || @state.shell_options['restricted_shell']
    end

    # Enable restricted mode (cannot be disabled once set)
    def enable_restricted_mode
      @state.set_options['r'] = true
      @state.shell_options['restricted_shell'] = true
    end

    # Check if shell is interactive
    def interactive_mode?
      @state.set_options['i']
    end

    # Enable interactive mode (read-only, set at startup)
    # Also enables monitor mode (job control) as per bash behavior
    def enable_interactive_mode
      @state.set_options['i'] = true
      @state.set_options['m'] = true  # Job control enabled for interactive shells
    end

    # List of variables that cannot be modified in restricted mode
    RESTRICTED_VARIABLES = %w[SHELL ENV PATH BASH_ENV SHELLOPTS RUBISHOPTS].freeze

    def set(args)
      # set [-+abCefhmnuvx] [-o option] [--] [arg...]
      # With no args, clear positional params (original behavior)
      if args.empty?
        @state.positional_params_setter&.call([])
        return true
      end

      i = 0
      while i < args.length
        arg = args[i]

        if arg == '--'
          # Everything after -- is positional params
          @state.positional_params_setter&.call(args[i + 1..] || [])
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
            if @state.set_options.key?(c)
              if c == 'r'
                # Enable restricted mode (syncs with restricted_shell shopt)
                enable_restricted_mode
              elsif c == 'i'
                # Cannot enable interactive mode via set (read-only)
                $stderr.puts 'rubish: set: interactive: cannot modify at runtime'
                return false
              else
                @state.set_options[c] = true
              end
            end
          end
        elsif arg.start_with?('+') && arg.length > 1
          # Disable short options: +e, +x
          arg[1..].each_char do |c|
            if @state.set_options.key?(c)
              if c == 'r' && restricted_mode?
                # Cannot disable restricted mode once enabled
                $stderr.puts 'rubish: set: restricted: cannot modify in restricted mode'
                return false
              elsif c == 'i'
                # Cannot disable interactive mode (read-only)
                $stderr.puts 'rubish: set: interactive: cannot modify at runtime'
                return false
              else
                @state.set_options[c] = false
              end
            end
          end
        else
          # Positional parameters
          @state.positional_params_setter&.call(args[i..])
          return true
        end
        i += 1
      end
      true
    end

    def list_set_options
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
      @state.set_options.each do |flag, value|
        name = long_names[flag] || flag
        state = value ? '-o' : '+o'
        puts "set #{state} #{name}"
      end
      true
    end

    # SHELLOPTS: colon-separated list of enabled set -o options
    def shellopts
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
      enabled = @state.set_options.select { |_, v| v }.keys.map { |k| long_names[k] || k }
      enabled.sort.join(':')
    end

    # RUBISHOPTS: colon-separated list of enabled shopt options (equivalent to BASHOPTS)
    def rubishopts
      enabled = []
      SHELL_OPTIONS.each_key do |name|
        if @state.shell_options.key?(name)
          enabled << name if @state.shell_options[name]
        elsif SHELL_OPTIONS[name][0]  # default value is true
          enabled << name
        end
      end
      enabled.sort.join(':')
    end

    # BASHOPTS: colon-separated list of enabled shopt options (read-only)
    # This is the bash-standard name; RUBISHOPTS is the rubish-specific equivalent
    def bashopts
      rubishopts
    end

    def set_long_option(name, value)
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
        @state.set_options['vi'] = true
        @state.set_options['emacs'] = false
        Reline.vi_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && value
        @state.set_options['emacs'] = true
        @state.set_options['vi'] = false
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'vi' && !value
        # Disabling vi enables emacs
        @state.set_options['vi'] = false
        @state.set_options['emacs'] = true
        Reline.emacs_editing_mode if defined?(Reline)
      elsif flag == 'emacs' && !value
        # Disabling emacs enables vi
        @state.set_options['emacs'] = false
        @state.set_options['vi'] = true
        Reline.vi_editing_mode if defined?(Reline)
      else
        @state.set_options[flag] = value
      end
    end

    def return_(args)
      code = args.first&.to_i || 0
      throw :return, code
    end

    def break_(args)
      # Optional: break N to break out of N levels (default 1)
      levels = args.first&.to_i || 1
      throw :break_loop, levels
    end

    def continue(args)
      # Optional: continue N to continue Nth enclosing loop (default 1)
      levels = args.first&.to_i || 1
      throw :continue_loop, levels
    end

    def true_(_args)
      true
    end

    def false_(_args)
      false
    end

    def test(args)
      # Remove trailing ] if called as [
      args = args[0...-1] if args.last == ']'

      return false if args.empty?

      # Handle compound expressions with -a (AND) and -o (OR)
      # -o has lower precedence than -a
      if args.include?('-o')
        idx = args.index('-o')
        left_result = test(args[0...idx])
        right_result = test(args[(idx + 1)..])
        return left_result || right_result
      end

      if args.include?('-a')
        idx = args.index('-a')
        left_result = test(args[0...idx])
        right_result = test(args[(idx + 1)..])
        return left_result && right_result
      end

      # Negation
      if args.first == '!'
        return !test(args[1..])
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

    def type(args)
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
          if @state.aliases.key?(name)
            found = true
            if type_only
              puts 'alias'
            elsif !path_only
              puts "#{name} is aliased to '#{@state.aliases[name]}'"
            end
            next unless show_all
          end
        end

        # Check function (unless force_path or suppress_functions)
        unless force_path || suppress_functions
          if @state.function_checker&.call(name)
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
    def execignore?(path)
      execignore = ENV['EXECIGNORE']
      return false if execignore.nil? || execignore.empty?

      patterns = execignore.split(':')
      patterns.any? do |pattern|
        next false if pattern.empty?
        File.fnmatch?(pattern, path, File::FNM_PATHNAME) ||
          File.fnmatch?(pattern, File.basename(path), File::FNM_PATHNAME)
      end
    end

    def find_in_path(name)
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
    def find_file_in_path(name)
      path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
      path_dirs.each do |dir|
        full_path = File.join(dir, name)
        return full_path if File.file?(full_path) && File.readable?(full_path)
      end
      nil
    end

    def find_all_in_path(name)
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

    def disown(args)
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

    def ulimit(args)
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

    def suspend(args)
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

    def shopt(args)
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
        return shopt_set_o(set_mode, unset_mode, print_mode, quiet_mode, opt_names)
      end

      # Helper to get current value of an option
      get_option = lambda do |name|
        if @state.shell_options.key?(name)
          @state.shell_options[name]
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
          COMPAT_OPTIONS.each { |opt| @state.shell_options[opt] = false }
        end

        @state.shell_options[name] = set_mode
      end

      true
    end

    # Handle shopt -o for set -o style options
    def shopt_set_o(set_mode, unset_mode, print_mode, quiet_mode, opt_names)
      # Build list of valid set -o option names (long names)
      valid_options = {}
      @state.set_options.each_key do |key|
        long_name = SET_O_LONG_NAMES[key] || key
        valid_options[long_name] = key
      end

      # Helper to get current value of a set -o option
      get_option = lambda do |name|
        key = valid_options[name]
        return nil unless key
        @state.set_options[key]
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
        @state.set_options[key] = set_mode
      end

      true
    end

    def shopt_enabled?(name)
      # Check @state.shell_options first (shopt -s)
      if @state.shell_options.key?(name)
        @state.shell_options[name]
      # Also check @state.set_options for options that can be set via both shopt and set -o
      elsif @state.set_options.key?(name) && @state.set_options[name]
        true
      elsif SHELL_OPTIONS.key?(name)
        SHELL_OPTIONS[name][0]
      else
        false
      end
    end

    # Set a shell option directly (for internal use)
    def set_shell_option(name, value)
      @state.shell_options[name] = value
    end

    # Normalize zsh option name: lowercase and remove underscores
    # zsh options are case-insensitive and underscores are ignored
    def normalize_zsh_option(name)
      name.downcase.gsub('_', '')
    end

    # Find the canonical zsh option name from a possibly non-canonical form
    def find_zsh_option(name)
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
    def zsh_option_enabled?(name)
      result = find_zsh_option(name)
      return false unless result

      type, canonical_name = result
      if type == :bash
        shopt_enabled?(canonical_name)
      else
        if @state.zsh_options.key?(canonical_name)
          @state.zsh_options[canonical_name]
        else
          ZSH_OPTIONS[canonical_name][0]  # default value
        end
      end
    end

    # Set a zsh option directly (for internal use)
    def set_zsh_option(name, value)
      result = find_zsh_option(name)
      return false unless result

      type, canonical_name = result
      if type == :bash
        @state.shell_options[canonical_name] = value
      else
        @state.zsh_options[canonical_name] = value
      end
      true
    end

    # setopt [+-options] [name ...]
    # Enable shell options (zsh-style)
    def setopt(args)
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
              @state.shell_options[canonical_name] = false
            else
              @state.zsh_options[canonical_name] = false
            end
            next
          end
        end

        result = find_zsh_option(arg)
        if result
          type, canonical_name = result
          if type == :bash
            @state.shell_options[canonical_name] = true
          else
            @state.zsh_options[canonical_name] = true
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
    def unsetopt(args)
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
              @state.shell_options[canonical_name] = true
            else
              @state.zsh_options[canonical_name] = true
            end
            next
          end
        end

        result = find_zsh_option(arg)
        if result
          type, canonical_name = result
          if type == :bash
            @state.shell_options[canonical_name] = false
          else
            @state.zsh_options[canonical_name] = false
          end
        else
          $stderr.puts "unsetopt: no such option: #{arg}"
          success = false
        end
      end

      success
    end

    # zsh autoload - mark functions for autoloading from fpath
    # Usage: autoload [-UXktz] [+X] [name ...]
    # Options:
    #   -U  suppress alias expansion during loading
    #   -z  use zsh-style autoloading (default)
    #   -k  use ksh-style autoloading
    #   -t  turn on tracing for the function
    #   -X  immediately load the function (used inside function stub)
    #   +X  load function immediately without executing
    def autoload(args)
      suppress_alias = false
      zsh_style = true
      ksh_style = false
      trace = false
      load_now = false
      load_only = false
      i = 0

      while i < args.length
        arg = args[i]
        if arg.start_with?('-') || arg.start_with?('+')
          arg.chars.each_with_index do |c, idx|
            next if idx == 0 && (c == '-' || c == '+')
            case c
            when 'U'
              suppress_alias = true
            when 'z'
              zsh_style = true
              ksh_style = false
            when 'k'
              ksh_style = true
              zsh_style = false
            when 't'
              trace = true
            when 'X'
              if arg.start_with?('+')
                load_only = true
              else
                load_now = true
              end
            else
              $stderr.puts "autoload: bad option: -#{c}"
              return false
            end
          end
        else
          break
        end
        i += 1
      end

      func_names = args[i..]

      # No function names - list all autoloaded functions
      if func_names.empty?
        @state.autoload_functions.each do |name, info|
          if info[:loaded]
            puts name
          else
            puts "#{name} (not yet loaded)"
          end
        end
        return true
      end

      # Process each function name
      func_names.each do |name|
        if load_now || load_only
          # Load the function immediately
          success = load_autoload_function(name)
          unless success
            $stderr.puts "autoload: can't load function definition for '#{name}'"
            return false
          end
        else
          # Mark for autoloading
          @state.autoload_functions[name] = {
            suppress_alias: suppress_alias,
            zsh_style: zsh_style,
            ksh_style: ksh_style,
            trace: trace,
            loaded: false
          }
        end
      end

      true
    end

    # Check if a function is marked for autoloading
    def autoload_pending?(name)
      @state.autoload_functions.key?(name) && !@state.autoload_functions[name][:loaded]
    end

    # Get fpath - the function search path
    def fpath
      fpath_str = ENV['FPATH'] || ENV['fpath'] || ''
      return [] if fpath_str.empty?

      fpath_str.split(':').reject(&:empty?)
    end

    # Set fpath
    def fpath=(paths)
      ENV['FPATH'] = paths.is_a?(Array) ? paths.join(':') : paths.to_s
    end

    # Load a function from fpath
    def load_autoload_function(name)
      fpath.each do |dir|
        func_file = File.join(dir, name)
        next unless File.exist?(func_file)

        begin
          content = File.read(func_file)

          # zsh-style: file contains function body directly
          # ksh-style: file contains function definition "name() { ... }"
          info = @state.autoload_functions[name] || {}

          if info[:ksh_style]
            # ksh-style: source the file directly
            @source_executor&.call(func_file)
          else
            # zsh-style: wrap content in function definition
            # The file contains just the function body
            func_def = "#{name}() {\n#{content}\n}"
            @source_executor&.call(nil, func_def)
          end

          @state.autoload_functions[name] = info.merge(loaded: true)
          return true
        rescue => e
          $stderr.puts "autoload: error loading #{name}: #{e.message}" if ENV['RUBISH_DEBUG']
        end
      end

      false
    end

    # Accessor for source executor (set by REPL)
    class << self
      attr_accessor :source_executor
    end

    # ==========================================================================
    # zsh completion system emulation
    # ==========================================================================

    @zsh_completion_initialized = false
    @zsh_completions = {}  # Hash of command names to completion function names

    class << self
      attr_accessor :zsh_completion_initialized, :zsh_completions
    end

    # compinit - initialize the zsh completion system
    # Usage: compinit [-u] [-d dumpfile] [-C]
    # Options:
    #   -u  use without checking for insecure directories
    #   -d  specify dump file for caching
    #   -C  skip checking for new completion functions
    def compinit(args)
      # Parse options (mostly ignored for compatibility)
      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when '-u', '-C'
          # Ignored - always behave as if these were set
        when '-d'
          i += 1  # Skip dump file argument
        when '-D'
          # Ignore -D (delete dump file)
        else
          break unless arg.start_with?('-')
        end
        i += 1
      end

      # Initialize the zsh completion system
      @zsh_completion_initialized = true

      # Set up default completions for common commands
      setup_zsh_default_completions

      true
    end

    # Set up default zsh-style completions
    def setup_zsh_default_completions
      # Map common commands to their completion types
      # These integrate with the existing bash-style completion system

      # File/directory completions
      %w[cat less more head tail vim vi nano emacs].each do |cmd|
        @state.completions[cmd] ||= {files: true}
      end

      # Directory-only completions
      %w[cd pushd].each do |cmd|
        @state.completions[cmd] ||= {directories: true}
      end

      # Git completions (if _git function exists or we have builtin)
      @state.completions['git'] ||= {function: '_git'}

      # SSH completions
      @state.completions['ssh'] ||= {function: '_ssh'}
      @state.completions['scp'] ||= {function: '_ssh'}

      # Make completions
      @state.completions['make'] ||= {function: '_make'}

      # Man completions
      @state.completions['man'] ||= {function: '_man'}

      # Kill completions (process IDs)
      @state.completions['kill'] ||= {function: '_kill'}
      @state.completions['killall'] ||= {signals: true, running: true}
    end

    # compdef - define zsh-style completion
    # Usage: compdef function command...
    #        compdef -n function command...  (don't override existing)
    #        compdef -d command...           (delete completion)
    #        compdef -p pattern function     (pattern-based completion)
    def compdef(args)
      return list_zsh_completions if args.empty?

      no_override = false
      delete_mode = false
      pattern_mode = false
      i = 0

      while i < args.length
        arg = args[i]
        case arg
        when '-n'
          no_override = true
        when '-d'
          delete_mode = true
        when '-p'
          pattern_mode = true
        when '-a'
          # Ignored - autoload function (we autoload automatically)
        else
          break unless arg.start_with?('-')
        end
        i += 1
      end

      remaining = args[i..]
      return true if remaining.empty?

      if delete_mode
        # Delete completions for specified commands
        remaining.each do |cmd|
          @state.completions.delete(cmd)
          @zsh_completions.delete(cmd)
        end
        return true
      end

      if pattern_mode
        # Pattern-based completion (simplified - just store the pattern)
        # compdef -p 'pattern' function
        if remaining.length >= 2
          pattern = remaining[0]
          func = remaining[1]
          @zsh_completions["pattern:#{pattern}"] = func
        end
        return true
      end

      # Standard mode: first arg is function, rest are commands
      func = remaining.shift
      return true if remaining.empty?

      remaining.each do |cmd|
        # Skip if no_override and completion already exists
        next if no_override && (@state.completions.key?(cmd) || @zsh_completions.key?(cmd))

        # Register the completion
        @zsh_completions[cmd] = func

        # Also register with bash-style system for integration
        # This allows the existing completion code to call the function
        @state.completions[cmd] = {function: func}
      end

      true
    end

    # __git_ps1 - Git prompt string generator (compatible with bash's git-prompt.sh)
    # Usage: __git_ps1 [format]
    # If format is provided, it's used as printf format with branch info as %s
    # Environment variables:
    #   GIT_PS1_SHOWDIRTYSTATE     - show * for unstaged, + for staged changes
    #   GIT_PS1_SHOWSTASHSTATE     - show $ if stash is not empty
    #   GIT_PS1_SHOWUNTRACKEDFILES - show % if there are untracked files
    #   GIT_PS1_SHOWUPSTREAM       - show <, >, <>, = for behind, ahead, diverged, up-to-date
    #   GIT_PS1_SHOWCOLORHINTS     - colorize the output
    #   GIT_PS1_DESCRIBE_STYLE     - how to show detached HEAD (contains, branch, describe, tag, default)
    def git_ps1(args)
      # Check if we're in a git repo
      git_dir = `git rev-parse --git-dir 2>/dev/null`.chomp
      return true if git_dir.empty?

      # Get branch name or commit
      branch = `git symbolic-ref --short HEAD 2>/dev/null`.chomp
      if branch.empty?
        # Detached HEAD - show commit or tag
        style = ENV['GIT_PS1_DESCRIBE_STYLE'] || 'default'
        branch = case style
                 when 'contains'
                   `git describe --contains HEAD 2>/dev/null`.chomp
                 when 'branch'
                   `git describe --contains --all HEAD 2>/dev/null`.chomp
                 when 'tag'
                   `git describe --tags HEAD 2>/dev/null`.chomp
                 when 'describe'
                   `git describe HEAD 2>/dev/null`.chomp
                 else
                   `git rev-parse --short HEAD 2>/dev/null`.chomp
                 end
        branch = "(#{branch})" unless branch.empty?
      end
      return true if branch.empty?

      state = +''

      # Show dirty state (* for unstaged, + for staged)
      if ENV['GIT_PS1_SHOWDIRTYSTATE']
        staged = !`git diff --cached --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        unstaged = !`git diff --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        state << '+' if staged
        state << '*' if unstaged
      end

      # Show stash state
      if ENV['GIT_PS1_SHOWSTASHSTATE']
        stash = `git stash list 2>/dev/null`.chomp
        state << '$' unless stash.empty?
      end

      # Show untracked files
      if ENV['GIT_PS1_SHOWUNTRACKEDFILES']
        untracked = `git ls-files --others --exclude-standard 2>/dev/null`.chomp
        state << '%' unless untracked.empty?
      end

      # Show upstream status
      upstream = ''
      if ENV['GIT_PS1_SHOWUPSTREAM']
        counts = `git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null`.chomp.split
        if counts.length == 2
          ahead, behind = counts.map(&:to_i)
          if ahead > 0 && behind > 0
            upstream = '<>'
          elsif ahead > 0
            upstream = '>'
          elsif behind > 0
            upstream = '<'
          else
            upstream = '='
          end
        end
      end

      # Build the git info string
      git_info = branch
      git_info += " #{state}" unless state.empty?
      git_info += upstream unless upstream.empty?

      # Apply colors if enabled
      if ENV['GIT_PS1_SHOWCOLORHINTS']
        if state.include?('*')
          git_info = "\e[31m#{git_info}\e[0m"  # Red for unstaged
        elsif state.include?('+')
          git_info = "\e[33m#{git_info}\e[0m"  # Yellow for staged only
        else
          git_info = "\e[32m#{git_info}\e[0m"  # Green for clean
        end
      end

      # Format output
      format = args.first || ' (%s)'
      puts format.gsub('%s', git_info)
      true
    end

    # List all zsh-style completions
    def list_zsh_completions
      @zsh_completions.each do |cmd, func|
        puts "#{cmd}: #{func}"
      end
      true
    end

    # Check if zsh completion is initialized
    def zsh_completion_initialized?
      @zsh_completion_initialized
    end

    # Get zsh completion function for a command
    def get_zsh_completion(cmd)
      @zsh_completions[cmd]
    end

    # List all currently enabled zsh options
    def list_enabled_zsh_options
      enabled = []

      # Bash-compatible options that are enabled
      ZSH_TO_BASH_OPTIONS.values.uniq.each do |bash_name|
        enabled << bash_name if shopt_enabled?(bash_name)
      end

      # Zsh-specific options that are enabled
      ZSH_OPTIONS.each do |name, (default, _desc)|
        value = @state.zsh_options.key?(name) ? @state.zsh_options[name] : default
        enabled << name if value
      end

      enabled.sort.each { |name| puts name }
    end

    # List all currently disabled zsh options
    def list_disabled_zsh_options
      disabled = []

      # Bash-compatible options that are disabled
      ZSH_TO_BASH_OPTIONS.values.uniq.each do |bash_name|
        disabled << bash_name unless shopt_enabled?(bash_name)
      end

      # Zsh-specific options that are disabled
      ZSH_OPTIONS.each do |name, (default, _desc)|
        value = @state.zsh_options.key?(name) ? @state.zsh_options[name] : default
        disabled << name unless value
      end

      disabled.sort.each { |name| puts name }
    end

    # Get current compatibility level from RUBISH_COMPAT or shopt compat* options
    # Returns a numeric version (e.g., 10 for 1.0) or nil if not set
    def compat_level
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
    def compat_level?(level)
      current = compat_level
      current && current <= level
    end

    # Get BASH_COMPAT value as a string (e.g., "5.1" or "51")
    # Returns empty string if no compat level is set (default mode)
    def bash_compat
      level = compat_level
      return '' unless level

      # Convert level to bash-style format (e.g., 51 -> "5.1" or "51")
      major = level / 10
      minor = level % 10
      "#{major}.#{minor}"
    end

    # Set compatibility level from BASH_COMPAT value
    # Accepts: "5.1", "51", 5.1, 51
    def set_bash_compat(value)
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
      COMPAT_OPTIONS.each { |opt| @state.shell_options[opt] = false }
      @state.shell_options[compat_opt] = true
    end

    # Clear all compat levels (return to default)
    def clear_compat_level
      COMPAT_OPTIONS.each { |opt| @state.shell_options[opt] = false }
    end

    # Set compatibility level (used when RUBISH_COMPAT is assigned)
    def set_compat_level(version)
      return unless version

      # Clear all compat options first
      COMPAT_OPTIONS.each { |opt| @state.shell_options[opt] = false }

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
      @state.shell_options[compat_opt] = true if SHELL_OPTIONS.key?(compat_opt)
    end

    # Check if POSIX mode is enabled via POSIXLY_CORRECT environment variable
    # In bash, POSIX mode is enabled when POSIXLY_CORRECT is set (even to empty string)
    def posix_mode?
      ENV.key?('POSIXLY_CORRECT')
    end

    # Track dynamically loaded builtins
    @loaded_builtins = {}  # name => { file: path, proc: callable }

    class << self
      attr_reader :loaded_builtins
    end

    def enable(args)
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
              Builtins.loaded_builtins[name] = {file: file_path, callable: mod.method(method_name)}
              Builtins.dynamic_commands << name unless Builtins.dynamic_commands.include?(name)
            elsif mod.const_defined?(name.upcase.tr('-', '_'), false)
              callable = mod.const_get(name.upcase.tr('-', '_'))
              Builtins.loaded_builtins[name] = {file: file_path, callable: callable}
              Builtins.dynamic_commands << name unless Builtins.dynamic_commands.include?(name)
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
          if Builtins.loaded_builtins.key?(name)
            Builtins.loaded_builtins.delete(name)
            Builtins.dynamic_commands.delete(name)
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

          enabled = !Builtins.disabled_builtins.include?(name)

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
          Builtins.disabled_builtins.add(name)
        else
          Builtins.disabled_builtins.delete(name)
        end
      end

      true
    end

    def find_loadable_file(filename)
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

    def caller(args)
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
      if Builtins.call_stack.empty?
        return false
      end

      # Check if frame is in range
      if frame >= Builtins.call_stack.length
        return false
      end

      # Get the frame (stack is stored with most recent first)
      # But caller 0 should be the immediate caller, so we need to reverse
      stack_frame = Builtins.call_stack[-(frame + 1)]
      return false unless stack_frame

      line_number, function_name, filename = stack_frame
      puts "#{line_number} #{function_name} #{filename}"
      true
    end

    def push_call_frame(line_number, function_name, filename)
      Builtins.call_stack.push([line_number, function_name, filename])
    end

    def pop_call_frame
      Builtins.call_stack.pop
    end

    def clear_call_stack
      Builtins.call_stack.clear
    end

    def complete(args)
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
              if COMPLETION_ACTION_FLAGS.key?(c)
                spec[:actions] << COMPLETION_ACTION_FLAGS[c]
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
          @state.completions.each do |name, s|
            puts format_completion_spec(name, s)
          end
        else
          # Print specified completions
          names.each do |name|
            if @state.completions.key?(name)
              puts format_completion_spec(name, @state.completions[name])
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
          @state.completions.clear
        else
          names.each do |name|
            @state.completions.delete(name)
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
        @state.completions[name] = spec.dup
      end

      true
    end

    def format_completion_spec(name, spec)
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

    def compgen(args)
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

      i = 0
      parsing_options = true
      while i < args.length
        arg = args[i]

        if parsing_options && arg.start_with?('-')
          case arg
          when '--'
            # End of options marker - remaining args are words
            parsing_options = false
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
              if COMPLETION_ACTION_FLAGS.key?(c)
                spec[:actions] << COMPLETION_ACTION_FLAGS[c]
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

    def generate_completions(spec, word = '')
      results = []

      (spec[:actions] || []).each do |action|
        case action
        when :alias
          results.concat(@state.aliases.keys.select { |a| a.start_with?(word) })
        when :arrayvar
          # Array variable names
          results.concat(@state.arrays.keys.select { |a| a.start_with?(word) })
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
          results.concat(Builtins.disabled_builtins.to_a.select { |b| b.start_with?(word) })
        when :enabled
          # Enabled builtin names (builtins not in disabled list)
          enabled = COMMANDS.reject { |c| Builtins.disabled_builtins.include?(c) }
          results.concat(enabled.select { |c| c.start_with?(word) })
        when :export
          ENV.keys.select { |k| k.start_with?(word) }.each { |k| results << k }
        when :file
          pattern = word.empty? ? '*' : "#{word}*"
          results.concat(Dir.glob(pattern))
        when :function
          # Shell function names
          functions = @state.function_lister&.call || {}
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

      # File completions (from -f option or zsh-style {files: true})
      if spec[:files]
        pattern = word.empty? ? '*' : "#{word}*"
        file_results = Dir.glob(pattern).map do |entry|
          File.directory?(entry) ? "#{entry}/" : entry
        end

        # Try abbreviated path expansion if no matches and word contains /
        if file_results.empty? && word.include?('/')
          file_results = expand_abbreviated_path_for_completion(word) || []
        end

        results.concat(file_results)
      end

      # Directory completions (from -d option or zsh-style {directories: true})
      if spec[:directories]
        pattern = word.empty? ? '*' : "#{word}*"
        Dir.glob(pattern).each do |entry|
          results << "#{entry}/" if File.directory?(entry)
        end
      end

      # Add prefix/suffix (-P/-S)
      if spec[:prefix] || spec[:suffix]
        results.map! do |r|
          "#{spec[:prefix]}#{r}#{spec[:suffix]}"
        end
      end

      results.uniq.sort
    end

    # Expand abbreviated path for completion: l/r/re -> ["l/r/repl.rb"]
    # Returns abbreviated form that starts with the user's input (for Reline filtering)
    def expand_abbreviated_path_for_completion(input, full_paths: false)
      # Split into directory part and filename part
      if input.end_with?('/')
        dir_part = input.chomp('/')
        file_prefix = ''
        abbreviated_prefix = input
      else
        dir_part = File.dirname(input)
        file_prefix = File.basename(input)
        abbreviated_prefix = dir_part == '.' ? '' : "#{dir_part}/"
      end

      # Expand the directory part
      expanded_dir = expand_abbreviated_dir(dir_part)
      return nil unless expanded_dir

      # Get completions from the expanded directory
      search_pattern = File.join(expanded_dir, "#{file_prefix}*")
      full_candidates = Dir.glob(search_pattern).map do |f|
        File.directory?(f) ? "#{f}/" : f
      end

      return nil if full_candidates.empty?

      # Return full paths or abbreviated form
      if full_paths
        full_candidates.sort
      else
        full_candidates.map do |full|
          filename = File.basename(full)
          filename = "#{filename}/" if full.end_with?('/')
          "#{abbreviated_prefix}#{filename}"
        end.sort
      end
    end

    # Expand abbreviated path: l/r/repl.rb -> lib/rubish/repl.rb
    # Returns single expanded path or nil
    def expand_abbreviated_path(path)
      return path if File.exist?(path)

      dir = File.dirname(path)
      filename = File.basename(path)

      expanded_dir = expand_abbreviated_dir(dir)
      return nil unless expanded_dir

      expanded_path = File.join(expanded_dir, filename)
      File.exist?(expanded_path) ? expanded_path : nil
    end

    # Expand abbreviated directory path: l/r -> lib/rubish
    def expand_abbreviated_dir(dir_path)
      return '.' if dir_path == '.'
      return dir_path if Dir.exist?(dir_path)

      segments = dir_path.split('/')
      return nil if segments.empty?

      # Handle absolute paths
      if dir_path.start_with?('/')
        current = '/'
        segments.shift if segments.first.empty?
      else
        current = '.'
      end

      segments.each do |segment|
        next if segment.empty?

        search_pattern = current == '.' ? "#{segment}*" : "#{current}/#{segment}*"
        matches = Dir.glob(search_pattern).select { |f| File.directory?(f) }

        if matches.length == 1
          current = matches.first
        elsif matches.empty?
          return nil
        else
          # Multiple matches - take the first one that starts with the segment
          match = matches.find { |m| File.basename(m).start_with?(segment) }
          return nil unless match
          current = match
        end
      end

      current == '.' ? nil : current
    end

    # Generate completions by calling a function (-F)
    def generate_function_completions(function_name, word)
      # Save current COMPREPLY (from the array, not instance variable)
      saved_compreply = get_array('COMPREPLY').dup

      # Clear COMPREPLY for the function
      set_array('COMPREPLY', [])
      @compreply = []

      # Set up completion context if not already set
      # The function expects: $1 = command name, $2 = word being completed, $3 = previous word
      cmd = @comp_words&.first || ''
      prev = @comp_cword && @comp_cword > 0 ? (@comp_words[@comp_cword - 1] || '') : ''

      begin
        # Try builtin completion function first
        if builtin_completion_function?(function_name)
          call_builtin_completion_function(function_name, cmd, word, prev)
        elsif @state.function_caller
          # Call user-defined function
          @state.function_caller.call(function_name, [cmd, word, prev])
        end

        # Return the results from COMPREPLY (from the array)
        get_array('COMPREPLY').dup
      ensure
        # Restore COMPREPLY
        set_array('COMPREPLY', saved_compreply)
        @compreply = saved_compreply
      end
    end

    # Generate completions by executing a command (-C)
    def generate_command_completions(command, word)
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
    def glob_to_regex(pattern)
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
    def get_hostnames
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
    def get_services
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

    def get_completion_spec(name)
      spec = @state.completions[name]
      return spec if spec

      # progcomp_alias: if name is an alias, use completion spec for the aliased command
      if shopt_enabled?('progcomp_alias') && @state.aliases.key?(name)
        # Get the first word of the alias expansion
        alias_value = @state.aliases[name]
        first_word = alias_value.split(/\s+/).first
        # Avoid infinite loop if alias points to itself
        return nil if first_word == name
        return @state.completions[first_word]
      end

      nil
    end

    def clear_completions
      @state.completions.clear
    end

    # Check if a function name is a builtin completion function
    def builtin_completion_function?(name)
      Builtins.builtin_completion_functions.key?(name)
    end

    # Call a builtin completion function
    # Returns true if function was called, false if not found
    def call_builtin_completion_function(name, cmd, cur, prev)
      func = Builtins.builtin_completion_functions[name]
      return false unless func
      ENV['cur'] = cur
      # Sync @compreply from array before calling
      @compreply = get_array('COMPREPLY')
      func.call(cmd, cur, prev)
      # Sync array from @compreply after calling
      set_array('COMPREPLY', @compreply)
      true
    end

    # Register builtin completion functions (class method for module loading)
    def self.register_builtin_completion_functions
      # _git - Git completion
      Builtins.builtin_completion_functions['_git'] = ->(cmd, cur, prev) { Builtins.context._git_completion(cmd, cur, prev) }

      # _ssh - SSH completion
      Builtins.builtin_completion_functions['_ssh'] = ->(cmd, cur, prev) { Builtins.context._ssh_completion(cmd, cur, prev) }

      # _cd - Directory completion
      Builtins.builtin_completion_functions['_cd'] = ->(cmd, cur, prev) { Builtins.context._cd_completion(cmd, cur, prev) }

      # _make - Make target completion
      Builtins.builtin_completion_functions['_make'] = ->(cmd, cur, prev) { Builtins.context._make_completion(cmd, cur, prev) }

      # _man - Man page completion
      Builtins.builtin_completion_functions['_man'] = ->(cmd, cur, prev) { Builtins.context._man_completion(cmd, cur, prev) }

      # _kill - Process completion
      Builtins.builtin_completion_functions['_kill'] = ->(cmd, cur, prev) { Builtins.context._kill_completion(cmd, cur, prev) }

      # _auto - Fish-style auto-completion by parsing --help
      Builtins.builtin_completion_functions['_auto'] = ->(cmd, cur, prev) { Builtins.context._auto_completion(cmd, cur, prev) }
    end

    # Initialize builtin completion functions on load
    register_builtin_completion_functions

    # Set up default completion specifications for common commands
    # This registers the builtin completion functions with the completion system
    def setup_default_completions
      # Git completion
      @state.completions['git'] = {actions: [], function: '_git'}

      # SSH/SCP/SFTP completion
      @state.completions['ssh'] = {actions: [], function: '_ssh'}
      @state.completions['scp'] = {actions: [], function: '_ssh'}
      @state.completions['sftp'] = {actions: [], function: '_ssh'}

      # CD completion (directories only)
      @state.completions['cd'] = {actions: [], function: '_cd'}
      @state.completions['pushd'] = {actions: [], function: '_cd'}

      # Make completion
      @state.completions['make'] = {actions: [], function: '_make'}
      @state.completions['gmake'] = {actions: [], function: '_make'}

      # Man page completion
      @state.completions['man'] = {actions: [], function: '_man'}

      # Kill completion
      @state.completions['kill'] = {actions: [], function: '_kill'}
      @state.completions['killall'] = {actions: [], function: '_kill'}
      @state.completions['pkill'] = {actions: [], function: '_kill'}
    end

    # ==========================================================================
    # CD completion function
    # ==========================================================================
    def _cd_completion(cmd, cur, prev)
      if cur.start_with?('-')
        @compreply = %w[-L -P -e -@].select { |opt| opt.start_with?(cur) }
        return
      end

      # Complete directories only
      _filedir(['-d'])
      @compreply = get_array('COMPREPLY')
    end

    # ==========================================================================
    # Make completion function
    # ==========================================================================
    def _make_completion(cmd, cur, prev)
      case prev
      when '-f', '--file', '--makefile'
        _filedir([])
        return
      when '-C', '--directory'
        _filedir(['-d'])
        return
      when '-I', '--include-dir'
        _filedir(['-d'])
        return
      when '-j', '--jobs', '-l', '--load-average'
        @compreply = []
        return
      when '-o', '--old-file', '--assume-old', '-W', '--what-if', '--new-file', '--assume-new'
        _filedir([])
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

    def _make_complete_targets(cur)
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
    def _man_completion(cmd, cur, prev)
      case prev
      when '-C', '--config-file', '-H', '--html', '-p', '--preprocessor'
        @compreply = []
        return
      when '-M', '--manpath'
        _filedir(['-d'])
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

    def _man_complete_pages(cur)
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
    def _kill_completion(cmd, cur, prev)
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

    def _kill_complete_signals(cur)
      @compreply = []
      signals = %w[HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1 SEGV USR2 PIPE
                   ALRM TERM STKFLT CHLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ
                   VTALRM PROF WINCH IO PWR SYS]
      @compreply = signals.select { |s| s.start_with?(cur.upcase) }
    end

    def _kill_complete_pids(cur)
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

    def compopt(args)
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
        enable_opts.each { |opt| @state.current_completion_options.add(opt) }
        disable_opts.each { |opt| @state.current_completion_options.delete(opt) }
      else
        # Apply to named commands
        targets = []
        targets << :default if apply_default
        targets << :empty if apply_empty
        targets.concat(names)

        targets.each do |name|
          @state.completion_options[name] ||= Set.new
          enable_opts.each { |opt| @state.completion_options[name].add(opt) }
          disable_opts.each { |opt| @state.completion_options[name].delete(opt) }
        end
      end

      true
    end

    def print_compopt_options(names, apply_default, apply_empty)
      targets = []
      targets << :default if apply_default
      targets << :empty if apply_empty
      targets.concat(names)

      if targets.empty?
        # Print current completion options
        if @state.current_completion_options.empty?
          puts 'compopt: no options set'
        else
          @state.current_completion_options.each { |opt| puts "compopt -o #{opt}" }
        end
      else
        targets.each do |name|
          opts = @state.completion_options[name] || Set.new
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

    def get_completion_options(name)
      @state.completion_options[name] || Set.new
    end

    def completion_option?(name, option)
      (@state.completion_options[name] || Set.new).include?(option)
    end

    def times(_args)
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

    def exec(args)
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
      exit_traps

      # Execute
      begin
        if clear_env
          # Clear environment and exec
          Kernel.exec([command, exec_argv0], *command_args, unsetenv_others: true)
        else
          Kernel.exec([command, exec_argv0], *command_args)
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

    def umask(args)
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

    def parse_umask(mode)
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

    def parse_symbolic_umask(mode)
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

    def umask_to_symbolic(mask)
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

    def kill(args)
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

    def wait(args)
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

    def builtin(args)
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

    def command(args)
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
      if @state.command_executor
        @state.command_executor.call(cmd_args)
        true
      else
        # Fallback: just use regular executor with the command
        # This won't bypass functions but at least runs something
        @state.executor&.call(cmd_args.join(' '))
        true
      end
    end

    def eval(args)
      # eval [arg ...]
      # Concatenate arguments and execute as a shell command
      return true if args.empty?

      command = args.join(' ')

      unless @state.executor
        puts 'eval: executor not configured'
        return false
      end

      begin
        @state.executor.call(command)
        true
      rescue => e
        puts "eval: #{e.message}"
        false
      end
    end

    def which(args)
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

    def exit(args)
      code = args.first&.to_i || 0

      # Check for active jobs if checkjobs is enabled
      if shopt_enabled?('checkjobs')
        active_jobs = JobManager.instance.active
        if active_jobs.any?
          if @state.exit_blocked_by_jobs
            # Second exit attempt - proceed with exit
            @state.exit_blocked_by_jobs = false
          else
            # First exit attempt - warn and block
            @state.exit_blocked_by_jobs = true
            running = active_jobs.count(&:running?)
            stopped = active_jobs.count(&:stopped?)
            parts = []
            parts << "#{running} running" if running > 0
            parts << "#{stopped} stopped" if stopped > 0
            $stderr.puts "rubish: there are #{parts.join(' and ')} jobs."
            return false
          end
        else
          @state.exit_blocked_by_jobs = false
        end
      end

      # huponexit: send SIGHUP to all jobs when an interactive login shell exits
      # Note: In bash, this only applies to login shells, but we apply it to interactive shells too
      if shopt_enabled?('huponexit')
        send_hup_to_active_jobs
      end

      exit_traps
      throw :exit, code
    end

    # Reset the exit blocked flag (call after any non-exit command)
    def clear_exit_blocked
      @state.exit_blocked_by_jobs = false
    end

    # Send SIGHUP to all active jobs (for huponexit)
    def send_hup_to_active_jobs
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

    def logout(args)
      # In bash, logout only works in login shells
      # For simplicity, we treat rubish as always being a login shell
      # and logout behaves the same as exit
      unless @state.shell_options['login_shell']
        # If not a login shell, warn but still exit (bash behavior varies)
        $stderr.puts 'logout: not login shell: use `exit\''
      end
      exit(args)
    end

    def jobs(_args)
      jobs = JobManager.instance.active
      if jobs.empty?
        # No output when no jobs
      else
        jobs.each { |job| puts job }
      end
      true
    end

    def fg(args)
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
      old_chld = Kernel.trap('CHLD', noop)
      old_ttou = Kernel.trap('TTOU', 'IGNORE')
      old_ttin = Kernel.trap('TTIN', 'IGNORE')

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
        Kernel.trap('CHLD', old_chld || 'DEFAULT')
        Kernel.trap('TTOU', old_ttou || 'DEFAULT')
        Kernel.trap('TTIN', old_ttin || 'DEFAULT')
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

    def bg(args)
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

    def find_job(args)
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

    def help(args)
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

    def print_all_builtins(short_desc)
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

    def print_help_for(cmd, short_desc: false, manpage: false, synopsis_only: false)
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

    def print_standard_format(cmd, info)
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

    def print_manpage_format(cmd, info)
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

    def wrap_text(text, width)
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

    def fc(args)
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

    def fc_reexecute(args, history)
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
      @state.executor&.call(cmd) if @state.executor
      true
    end

    def fc_resolve_range(first_arg, last_arg, history, list_mode)
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

    def fc_parse_history_ref(ref, history)
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

    def fc_get_range(history, first_idx, last_idx)
      if first_idx <= last_idx
        (first_idx..last_idx).map { |i| [i + 1, history[i]] }
      else
        (last_idx..first_idx).map { |i| [i + 1, history[i]] }.reverse
      end
    end

    def fc_list_commands(commands, first_idx, last_idx, reverse_order, suppress_numbers)
      commands.each do |num, cmd|
        if suppress_numbers
          puts cmd
        else
          puts format('%5d  %s', num, cmd)
        end
      end
    end

    def fc_edit_and_execute(commands, editor)
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
          @state.executor&.call(line) if @state.executor
        end

        true
      ensure
        tempfile.unlink
      end
    end

    def mapfile(args)
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
          @state.executor&.call("#{callback} #{idx} #{line.inspect}")
        end
      end

      # Set array length marker
      ENV["#{array_name}_LENGTH"] = lines.length.to_s

      true
    end

    # Helper to get mapfile array contents
    def get_mapfile_array(name = 'MAPFILE')
      length = ENV["#{name}_LENGTH"]&.to_i || 0
      (0...length).map { |i| ENV["#{name}_#{i}"] }
    end

    # Helper to clear mapfile array
    def clear_mapfile_array(name = 'MAPFILE')
      ENV.keys.select { |k| k.start_with?("#{name}_") }.each { |k| ENV.delete(k) }
    end

    def basename(args)
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

    def dirname(args)
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

    def realpath(args)
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

    def require(args)
      # require NAME
      # Calls Ruby's require method to load a library
      if args.empty?
        $stderr.puts 'require: missing operand'
        return false
      end

      name = args.first
      begin
        Kernel.require name
        true
      rescue LoadError => e
        $stderr.puts "require: #{e.message}"
        false
      rescue => e
        $stderr.puts "require: #{name}: #{e.message}"
        false
      end
    end

    # Wrapper for head command to support Ruby-like syntax: head(5) -> head -5
    def head(args)
      head_tail_wrapper('head', args)
    end

    # Wrapper for tail command to support Ruby-like syntax: tail(5) -> tail -5
    def tail(args)
      head_tail_wrapper('tail', args)
    end

    # Common wrapper for head/tail that converts bare positive integers to -n form
    def head_tail_wrapper(cmd, args)
      # Transform args: convert bare positive integers to -n form
      # e.g., head(5) -> head -n 5, tail(10) -> tail -n 10
      # But don't transform if preceded by -n or -c (already has the flag)
      transformed_args = []
      skip_transform = false

      args.each do |arg|
        if skip_transform
          transformed_args << arg
          skip_transform = false
        elsif arg == '-n' || arg == '-c'
          transformed_args << arg
          skip_transform = true  # Next arg is already the value for this flag
        elsif arg =~ /\A\d+\z/
          # Bare positive integer -> -n <number>
          transformed_args << '-n'
          transformed_args << arg
        else
          transformed_args << arg
        end
      end

      # Execute the external command with transformed args
      pid = Process.spawn(cmd, *transformed_args)
      _, status = Process.wait2(pid)
      status.success?
    rescue Errno::ENOENT
      $stderr.puts "#{cmd}: command not found"
      false
    end

    def extract_unquoted_keywords(line)
      # Extract shell keywords and braces from a line while respecting quotes
      # Returns array of keywords found outside of quoted sections
      # This prevents counting { } inside awk scripts like: awk '{ print $1 }'
      # Also handles inline comments: echo foo # for  (the 'for' is in a comment)
      keywords = []
      in_single_quotes = false
      in_double_quotes = false
      current_word = +''
      i = 0

      while i < line.length
        char = line[i]

        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          i += 1
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          i += 1
        elsif char == '\\' && !in_single_quotes
          # Skip escaped character
          i += 2
        elsif !in_single_quotes && !in_double_quotes
          if char == '#'
            # Start of comment - stop processing the rest of the line
            keywords << current_word unless current_word.empty?
            break
          elsif char =~ /\s/
            # End of word
            keywords << current_word unless current_word.empty?
            current_word = +''
            i += 1
          else
            current_word << char
            i += 1
          end
        else
          # Inside quotes, skip
          i += 1
        end
      end

      # Don't forget the last word (if we didn't hit a comment)
      keywords << current_word unless current_word.empty?

      # Filter to only control structure keywords and braces
      keywords.select { |w| %w[if unless while until for case def fi done esac end { }].include?(w) }
    end

    def has_unclosed_quotes(text)
      # Check if the text has unclosed single or double quotes
      # Returns true if there are unclosed quotes (meaning we need more input)
      in_single_quotes = false
      in_double_quotes = false
      i = 0

      while i < text.length
        char = text[i]

        if char == "'" && !in_double_quotes
          in_single_quotes = !in_single_quotes
          i += 1
        elsif char == '"' && !in_single_quotes
          in_double_quotes = !in_double_quotes
          i += 1
        elsif char == '\\' && !in_single_quotes
          # Skip escaped character (backslash only escapes in double quotes or unquoted)
          i += 2
        else
          i += 1
        end
      end

      in_single_quotes || in_double_quotes
    end

    def detect_heredoc(line)
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
