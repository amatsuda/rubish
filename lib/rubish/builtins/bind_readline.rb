# frozen_string_literal: true

module Rubish
  module Builtins
    # READLINE_LINE - contents of the readline buffer during bind -x execution
    def readline_line
      @state.readline_line_getter&.call || ''
    end

    def readline_line=(value)
      @state.readline_line_setter&.call(value.to_s)
    end

    # READLINE_POINT - cursor position (index) in READLINE_LINE during bind -x execution
    def readline_point
      @state.readline_point_getter&.call || 0
    end

    def readline_point=(value)
      @state.readline_point_setter&.call(value.to_i)
      @state.readline_point_modified = true
    end

    # READLINE_MARK - mark position in READLINE_LINE during bind -x execution
    def readline_mark
      @state.readline_mark_getter&.call || 0
    end

    def readline_mark=(value)
      @state.readline_mark_setter&.call(value.to_i)
    end

    # Track if READLINE_POINT was explicitly modified during bind -x
    def readline_point_modified
      @state.readline_point_modified
    end

    def readline_point_modified=(value)
      @state.readline_point_modified = value
    end

    # Executor for bind -x commands
    def bind_x_executor
      @state.bind_x_executor
    end

    def bind_x_executor=(value)
      @state.bind_x_executor = value
    end

    def bind(args)
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
        # First show Reline's actual key bindings
        get_reline_key_bindings.each do |keyseq, action|
          puts "\"#{escape_keyseq(keyseq)}\": #{action}"
        end
        # Then show any additional bindings from @key_bindings
        @state.key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": #{binding[:value]}"
        end
        return true
      end

      # Print key bindings with function names
      if print_bindings
        # First show Reline's actual key bindings
        get_reline_key_bindings.each do |keyseq, action|
          puts "#{escape_keyseq(keyseq)} can be found in #{action}."
        end
        # Then show any additional bindings from @key_bindings
        @state.key_bindings.each do |keyseq, binding|
          next if binding[:type] == :macro || binding[:type] == :command

          puts "#{escape_keyseq(keyseq)} can be found in #{binding[:value]}."
        end
        return true
      end

      # Print macros in reusable format
      if print_macros_readable
        @state.key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :macro

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Print macros
      if print_macros
        @state.key_bindings.each do |keyseq, binding|
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
        @state.key_bindings.each do |keyseq, binding|
          next unless binding[:type] == :command

          puts "\"#{escape_keyseq(keyseq)}\": \"#{binding[:value]}\""
        end
        return true
      end

      # Query which keys invoke a function
      if query_function
        found = false
        @state.key_bindings.each do |keyseq, binding|
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
        @state.key_bindings.delete_if { |_, binding| binding[:value] == unbind_function }
        return true
      end

      # Remove binding for keyseq
      if remove_keyseq
        @state.key_bindings.delete(remove_keyseq)
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
          @state.key_bindings[keyseq] = {type: :command, value: command, keymap: keymap}
          # Register with Reline for actual execution
          register_bind_x_with_reline(keyseq, command, keymap)
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

    def parse_and_add_binding(binding_str, keymap = 'emacs')
      keyseq, value = binding_str.split(':', 2)
      return unless keyseq && value

      keyseq = unescape_keyseq(keyseq.delete('"').strip)
      value = value.strip

      # Determine if it's a function or macro
      if value.start_with?('"') && value.end_with?('"')
        # Macro
        @state.key_bindings[keyseq] = {type: :macro, value: value[1..-2], keymap: keymap}
      else
        # Function
        @state.key_bindings[keyseq] = {type: :function, value: value, keymap: keymap}
      end
    end

    # Get Reline's actual key bindings as a hash of keyseq string => action symbol
    # Combines bindings from both @additional_key_bindings (higher priority, from inputrc/custom)
    # and @default_key_bindings (lower priority, built-in defaults)
    def get_reline_key_bindings
      result = {}
      begin
        config = Reline.core.config
        editing_mode = config.instance_variable_get(:@editing_mode_label) || :emacs

        # First, get default key bindings (lowest priority)
        default_bindings = config.instance_variable_get(:@default_key_bindings)
        if default_bindings && default_bindings[editing_mode]
          bindings = default_bindings[editing_mode].instance_variable_get(:@key_bindings)
          bindings&.each do |seq, action|
            next if action == :ed_insert || action == :ed_digit
            keyseq = seq.pack('C*')
            result[keyseq] = action
          end
        end

        # Then, get additional key bindings (higher priority, will override defaults)
        additional_bindings = config.instance_variable_get(:@additional_key_bindings)
        if additional_bindings && additional_bindings[editing_mode]
          bindings = additional_bindings[editing_mode].instance_variable_get(:@key_bindings)
          bindings&.each do |seq, action|
            next if action == :ed_insert || action == :ed_digit
            keyseq = seq.pack('C*')
            result[keyseq] = action
          end
        end
      rescue
        # Reline not available or error accessing bindings
      end
      result
    end

    def escape_keyseq(keyseq)
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

    def unescape_keyseq(keyseq)
      result = keyseq.dup

      # Handle meta escape sequences first (\M-x)
      result.gsub!(/\\M-\\C-([a-zA-Z@\[\]\\^_?])/) do |_|
        char = ::Regexp.last_match(1)
        if char == '?'
          (0x80 | 0x7F).chr  # Meta-DEL
        else
          (0x80 | (char.upcase.ord & 0x1F)).chr
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
        char = ::Regexp.last_match(1)
        (char.upcase.ord & 0x1F).chr
      end

      # Handle control characters \C-? format for DEL
      result.gsub!('\\C-?', "\x7F")

      # Handle ^x control character format
      result.gsub!(/\^([a-zA-Z@\[\]\\^_?])/) do |_|
        char = ::Regexp.last_match(1)
        if char == '?'
          "\x7F"  # DEL
        else
          (char.upcase.ord & 0x1F).chr
        end
      end

      result
    end

    def get_key_binding(keyseq)
      @state.key_bindings[keyseq]
    end

    def clear_key_bindings
      @state.key_bindings.clear
      @state.readline_variables.clear
    end

    # Register a bind -x shell command with Reline for actual execution
    def register_bind_x_with_reline(keyseq, command, keymap)
      return unless defined?(Reline)

      # Generate a unique method name for this binding
      method_name = :"__rubish_bind_x_#{@state.bind_x_counter}"
      @state.bind_x_counter += 1

      # Store the command in the binding for lookup
      @state.key_bindings[keyseq][:method_name] = method_name

      # Define the method on Reline::LineEditor
      # We need to capture 'command' and 'self' (Builtins) in the closure
      builtins = self
      Reline::LineEditor.define_method(method_name) do |key = nil, **kwargs|
        # Get current line and cursor position from the line editor
        current_line = whole_buffer
        current_point = byte_pointer

        # Set READLINE_LINE, READLINE_POINT, READLINE_MARK
        builtins.readline_line = current_line
        builtins.readline_point = current_point
        builtins.readline_mark = 0

        # Track if READLINE_POINT is explicitly modified
        builtins.readline_point_modified = false

        # Execute the shell command
        if builtins.bind_x_executor
          begin
            builtins.bind_x_executor.call(command)
          rescue => e
            $stderr.puts "bind -x: #{e.message}" if ENV['RUBISH_DEBUG']
          end
        end

        # Check if READLINE_LINE was modified
        new_line = builtins.readline_line || current_line
        new_point = builtins.readline_point
        point_was_modified = builtins.readline_point_modified

        # Update the line buffer if it changed
        if new_line != current_line
          # Clear and replace the buffer
          @buffer_of_lines = new_line.split("\n", -1)
          @buffer_of_lines = [''] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.length - 1
        end

        # Update cursor position
        if point_was_modified
          # READLINE_POINT was explicitly set - use it
          self.byte_pointer = [new_point, new_line.bytesize].min
        elsif new_line != current_line
          # Line changed but point not explicitly set - move to end
          self.byte_pointer = new_line.bytesize
        end
      end

      # Convert keymap name to Reline keymap symbol
      reline_keymap = case keymap
                      when 'vi', 'vi-command' then :vi_command
                      when 'vi-insert' then :vi_insert
                      else :emacs
                      end

      # Register the key binding with Reline
      keystroke = keyseq.bytes.to_a
      Reline.core.config.add_default_key_binding_by_keymap(reline_keymap, keystroke, method_name)
    end

    # Apply a readline variable to Reline (if applicable)
    def apply_readline_variable(var, value)
      @state.readline_variables[var] = value

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
    def get_readline_variable(var)
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
      @state.readline_variables[var]
    end

    def bindkey(args)
      keymap = nil
      list_keymaps = false
      remove_key = nil
      macro_binding = false
      i = 0

      while i < args.length
        arg = args[i]

        if arg.start_with?('-')
          case arg
          when '-l'
            list_keymaps = true
          when '-L'
            # List in bindkey command format (same as no args for now)
            return list_bindkey_bindings(keymap)
          when '-M'
            i += 1
            keymap = args[i] if args[i]
          when '-e'
            # Select emacs keymap
            select_keymap('emacs')
            return true
          when '-v'
            # Select viins keymap
            select_keymap('viins')
            return true
          when '-a'
            # Select vicmd keymap
            select_keymap('vicmd')
            return true
          when '-r'
            i += 1
            remove_key = args[i] if args[i]
          when '-s'
            macro_binding = true
          else
            $stderr.puts "bindkey: bad option: #{arg}"
            return false
          end
        else
          # Non-option argument
          break
        end
        i += 1
      end

      # List keymap names
      if list_keymaps
        puts 'emacs'
        puts 'viins'
        puts 'vicmd'
        puts 'visual'
        puts 'isearch'
        puts 'command'
        puts 'main'
        return true
      end

      # Remove binding
      if remove_key
        keyseq = parse_bindkey_keyseq(remove_key)
        @state.key_bindings.delete(keyseq)
        return true
      end

      remaining_args = args[i..]

      # No more args - list all bindings
      if remaining_args.empty?
        return list_bindkey_bindings(keymap)
      end

      # One arg - show binding for that key
      if remaining_args.length == 1
        keyseq = parse_bindkey_keyseq(remaining_args[0])
        binding = @state.key_bindings[keyseq]
        if binding
          puts "\"#{format_bindkey_keyseq(keyseq)}\" #{binding[:value]}"
        else
          puts "\"#{format_bindkey_keyseq(keyseq)}\" undefined-key"
        end
        return true
      end

      # Two args - bind key to widget/macro
      keyseq = parse_bindkey_keyseq(remaining_args[0])
      value = remaining_args[1]

      if macro_binding
        # -s: bind to macro (string output)
        @state.key_bindings[keyseq] = {type: :macro, value: parse_bindkey_keyseq(value), keymap: keymap || 'main'}
      else
        # Bind to widget (function)
        @state.key_bindings[keyseq] = {type: :function, value: value, keymap: keymap || 'main'}
      end

      true
    end

    # Parse zsh-style key sequence (e.g., "^A", "^[a", "\e[A")
    def parse_bindkey_keyseq(str)
      return str if str.nil? || str.empty?

      result = +''
      i = 0

      # Remove surrounding quotes if present
      if (str.start_with?('"') && str.end_with?('"')) ||
         (str.start_with?("'") && str.end_with?("'"))
        str = str[1...-1]
      end

      while i < str.length
        char = str[i]

        if char == '^' && i + 1 < str.length
          # ^X -> Ctrl-X
          next_char = str[i + 1]
          if next_char == '?'
            result << "\x7F"  # DEL
          elsif next_char == '['
            result << "\e"  # ESC
          else
            # Convert to control character
            result << (next_char.upcase.ord & 0x1F).chr
          end
          i += 2
        elsif char == '\\' && i + 1 < str.length
          next_char = str[i + 1]
          case next_char
          when 'e', 'E'
            result << "\e"
            i += 2
          when 'n'
            result << "\n"
            i += 2
          when 'r'
            result << "\r"
            i += 2
          when 't'
            result << "\t"
            i += 2
          when '\\'
            result << '\\'
            i += 2
          when 'C'
            # \C-x -> Ctrl-x
            if i + 3 < str.length && str[i + 2] == '-'
              ctrl_char = str[i + 3]
              result << (ctrl_char.upcase.ord & 0x1F).chr
              i += 4
            else
              result << char
              i += 1
            end
          when 'M'
            # \M-x -> Meta-x (ESC + x)
            if i + 3 < str.length && str[i + 2] == '-'
              result << "\e" << str[i + 3]
              i += 4
            else
              result << char
              i += 1
            end
          else
            result << next_char
            i += 2
          end
        else
          result << char
          i += 1
        end
      end

      result
    end

    # Format key sequence for display
    def format_bindkey_keyseq(keyseq)
      return '' if keyseq.nil? || keyseq.empty?

      result = +''
      keyseq.each_char do |char|
        ord = char.ord
        if ord < 32
          if ord == 27
            result << '^['
          else
            result << '^' << (ord + 64).chr
          end
        elsif ord == 127
          result << '^?'
        else
          result << char
        end
      end
      result
    end

    # List all key bindings in bindkey format
    def list_bindkey_bindings(keymap = nil)
      if @state.key_bindings.empty?
        # Show some default bindings
        puts '"^A" beginning-of-line'
        puts '"^E" end-of-line'
        puts '"^K" kill-line'
        puts '"^U" unix-line-discard'
        puts '"^W" backward-kill-word'
        return true
      end

      @state.key_bindings.each do |keyseq, binding|
        next if keymap && binding[:keymap] != keymap

        formatted_key = format_bindkey_keyseq(keyseq)
        case binding[:type]
        when :function
          puts "\"#{formatted_key}\" #{binding[:value]}"
        when :macro
          puts "\"#{formatted_key}\" \"#{format_bindkey_keyseq(binding[:value])}\""
        when :command
          puts "\"#{formatted_key}\" \"#{binding[:value]}\""
        end
      end
      true
    end

    # Select a keymap (emacs or vi)
    def select_keymap(keymap)
      case keymap
      when 'emacs', 'main'
        apply_readline_variable('editing-mode', 'emacs')
      when 'viins', 'vicmd', 'vi'
        apply_readline_variable('editing-mode', 'vi')
      end
    end
  end
end
