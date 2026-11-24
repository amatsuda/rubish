# frozen_string_literal: true

module Rubish
  # Runtime methods called from generated Ruby code (codegen output)
  # Methods in this module have __ prefix and are the interface between
  # codegen and the shell execution
  module Runtime
    # === Arithmetic methods ===

    def __arith_for_loop(init_expr, cond_expr, update_expr, &block)
      # C-style arithmetic for loop: for ((init; cond; update)); do body; done
      # Evaluate init expression once
      eval_arithmetic_expr(init_expr) unless init_expr.empty?

      # Loop while condition is true (non-zero)
      loop do
        # If condition is empty, it's always true (infinite loop)
        unless cond_expr.empty?
          result = eval_arithmetic_expr(cond_expr)
          break if result == 0  # Condition is false
        end

        # Execute body
        block.call

        # Evaluate update expression
        eval_arithmetic_expr(update_expr) unless update_expr.empty?
      end
    end

    def __arith(expr)
      # Evaluate arithmetic expression
      eval_arithmetic_expr(expr).to_s
    end

    def __arithmetic_command(expr)
      # Evaluate (( )) arithmetic command
      # Returns exit status 0 if result is non-zero, 1 if result is zero
      # Supports variable assignments like x=1, x++, x--, ++x, --x, x+=1, etc.
      announce_texts(["(( #{expr} ))"])
      result = eval_arithmetic_expr(expr)
      ExitStatus.new(result != 0 ? 0 : 1)
    end

    # === Expansion methods ===

    # Run command substitution within rubish itself (not external shell)
    # This allows user-defined functions to be available in $() substitution
    # Forks a subprocess, captures stdout, and returns the output (with trailing newlines removed)
    # Builtins that only produce output: a $(...) made of one of these can
    # run in this process (capturing $stdout) instead of forking the whole
    # interpreter, which costs several milliseconds per substitution.
    # Anything that touches shell state (cd, read, printf -v, ...) is left
    # to the subshell so that its effects stay there.
    SUBST_IN_PROCESS_BUILTINS = %w[echo printf pwd basename dirname realpath true false].freeze

    def __run_subst(cmd)
      # A command substitution is a subshell level for BASH_SUBSHELL, even
      # when its builtin runs in this process
      Builtins.subshell_level += 1
      begin
        in_process = __subst_in_process(cmd)
      ensure
        Builtins.subshell_level -= 1
      end
      return in_process unless in_process.nil?

      reader, writer = IO.pipe
      # inherit_errexit: if disabled, child should not inherit errexit (set -e)
      inherit_errexit = Builtins.shopt_enabled?('inherit_errexit')

      pid = fork do
        reader.close
        Builtins.subshell_level += 1
        @proc_sub_fds = nil # the parent owns the pipe ends it keeps
        # Redirect stdout to the pipe using the constant STDOUT
        # This works even if $stdout has been redirected to a StringIO (for testing)
        STDOUT.reopen(writer)
        $stdout = STDOUT

        # Suppress stderr during completion to avoid spurious output on terminal
        if Builtins.in_completion_context?
          STDERR.reopen(File.open(File::NULL, 'w'))
          $stderr = STDERR
        end

        # Command substitution only inherits errexit when inherit_errexit is enabled
        Builtins.current_state.set_options['e'] = false unless inherit_errexit

        # Disable job control inside the substitution. Otherwise the
        # inner pipeline would fork into its own process group and lose
        # the controlling terminal, so interactive tools like peco /
        # fzf / less that need /dev/tty for their TUI get
        # SIGTTIN/SIGTTOU and the shell prints "[1]+ Stopped …" into
        # our capture pipe instead of the tool's real output. bash and
        # zsh do the same — `set -m` is off inside `$(…)`.
        Builtins.current_state.set_options['m'] = false

        begin
          exit_code = catch(:exit) do
            execute(cmd, skip_history_expansion: true)
            @last_status
          end
          Kernel.exit(exit_code || @last_status || 0)
        rescue => e
          $stderr.puts "rubish: #{e.message}" unless Builtins.in_completion_context?
          Kernel.exit(1)
        end
      end

      writer.close
      output = reader.read.sub(/\n+\z/, '')
      reader.close

      Process.wait(pid)
      @last_status = ExitStatus.code_of($?)
      # Remembered so a bare assignment (`x=$(cmd)`) can report this status
      @last_subst_status = @last_status
      output
    end

    # Run `cmd` here when it is a lone output-only builtin; nil means "not
    # eligible, fork as usual". Functions and aliases take precedence over
    # builtins, so their presence disables the shortcut for that name.
    def __subst_in_process(cmd)
      # $(< file): the file's contents, trailing newlines dropped (bash)
      if cmd =~ /\A\s*<\s*([^\s<>|&;]+)\s*\z/
        path = expand_string_content($1)
        begin
          @last_status = @last_subst_status = 0
          return File.read(path).sub(/\n+\z/, '')
        rescue SystemCallError => e
          $stderr.puts "rubish: #{path}: #{e.class.new.message}"
          @last_status = @last_subst_status = 1
          return ''
        end
      end

      return nil if cmd.include?("\n") || Builtins.set_option?('x')

      ast = Parser.new(Lexer.new(cmd).tokenize).parse
      return nil unless ast.is_a?(AST::Command) && ast.block.nil? && ast.env.empty?

      name = ast.name
      return nil unless SUBST_IN_PROCESS_BUILTINS.include?(name)
      return nil if name == 'printf' && ast.args.first.to_s.start_with?('-v')
      return nil if Command.function?(name) || Builtins.current_state.aliases.key?(name)

      args = expand_args_for_builtin(ast.args)
      captured = StringIO.new
      saved_stdout = $stdout
      $stdout = captured
      begin
        success = Builtins.run(name, args)
      ensure
        $stdout = saved_stdout
      end
      @last_status = success.is_a?(ExitStatus) ? success.exitstatus : (success ? 0 : 1)
      @last_subst_status = @last_status
      captured.string.sub(/\n+\z/, '')
    rescue ArithmeticEvaluator::Error, NounsetError, FailglobError, ParameterExpansionError
      raise
    rescue StandardError
      # Lexer/parser could not handle it: let the subshell deal with it
      nil
    end

    # Parameter expansion operations
    # Operators:
    #   :-  Use default if unset or null
    #   -   Use default only if unset (null is fine)
    #   :=  Assign default if unset or null
    #   =   Assign default only if unset
    #   :+  Use value if set and non-null
    #   +   Use value if set (even if null)
    #   :?  Error if unset or null
    #   ?   Error only if unset
    #   #   Remove shortest prefix matching pattern
    #   ##  Remove longest prefix matching pattern
    #   %   Remove shortest suffix matching pattern
    #   %%  Remove longest suffix matching pattern
    def __param_expand(var_name, operator, operand, expand_operand: false)
      # The operand word is only expanded when the operator actually uses
      # it, like bash: `${X-$(cmd)}` must not run cmd when X is set. The
      # codegen path defers its interpolation by passing a proc; the
      # runtime path passes the raw text with expand_operand: true so
      # $VAR / $(cmd) / backticks inside it are expanded here
      # (`brew shellenv` relies on `${PATH+:$PATH}` splicing in old PATH).
      resolve = lambda do
        word = operand.respond_to?(:call) ? operand.call.to_s : operand
        # extquote: when enabled, process $'...' and $"..." quoting in the operand
        word = expand_extquote(word) if Builtins.shopt_enabled?('extquote')
        word = expand_string_content(word, quoted: true) if expand_operand
        word
      end

      if %w[# ## % %%].include?(operator) &&
         (words = __each_param_element(var_name) { |scratch| __param_expand(scratch, operator, operand, expand_operand: expand_operand) })
        return words.join(' ')
      end

      value, is_set, is_null = get_param_expand_info(var_name)

      case operator
      when ':-' then is_null ? resolve.call : value                    # ${var:-default}
      when '-' then is_set ? value : resolve.call                      # ${var-default}
      when ':=' then is_null ? assign_default(var_name, resolve.call) : value  # ${var:=default}
      when '=' then is_set ? value : assign_default(var_name, resolve.call)    # ${var=default}
      when ':+' then is_null ? '' : resolve.call                       # ${var:+value}
      when '+' then is_set ? resolve.call : ''                         # ${var+value}
      when ':?'                                                        # ${var:?message}
        if is_null
          message = resolve.call
          message = 'parameter null or not set' if message.empty?
          raise ParameterExpansionError, "#{var_name}: #{message}"
        end
        value
      when '?'                                                         # ${var?message}
        unless is_set
          message = resolve.call
          message = 'parameter not set' if message.empty?
          raise ParameterExpansionError, "#{var_name}: #{message}"
        end
        value || ''
      when '#'                                                         # ${var#pattern}
        return '' if value.nil?
        pattern_to_regex(resolve.call, :prefix, :shortest).match(value) { |m| value[m.end(0)..] } || value
      when '##'                                                        # ${var##pattern}
        return '' if value.nil?
        pattern_to_regex(resolve.call, :prefix, :longest).match(value) { |m| value[m.end(0)..] } || value
      when '%' then value.nil? ? '' : remove_suffix(value, resolve.call, :shortest)   # ${var%pattern}
      when '%%' then value.nil? ? '' : remove_suffix(value, resolve.call, :longest)   # ${var%%pattern}
      else value || ''
      end
    end

    # ${#var} - length of variable value
    def __param_length(var_name)
      if Builtins.set_option?('u') && var_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) && !Builtins.var_set?(var_name) && !Builtins.array?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      (__param_value(var_name) || '').length.to_s
    end

    # $N: an unset positional parameter is an error under set -u, as in bash
    def __positional(n)
      value = positional_params[n - 1]
      if value.nil? && Builtins.set_option?('u')
        $stderr.puts Builtins.format_error('unbound variable', command: "$#{n}")
        raise NounsetError, "$#{n}: unbound variable"
      end
      value || ''
    end

    # ${var:offset} or ${var:offset:length} - substring extraction
    # ${var:offset[:length]}. Offset and length are arithmetic expressions
    # (so `${s:i+1}`, `${s:(-3)}` and `${s: -2}` all work); a negative offset
    # counts from the end, a negative length leaves that many characters off
    # the end.
    def __param_substring(var_name, offset, length)
      value = if var_name.match?(/\A[1-9]\d*\z/)
                __positional(var_name.to_i).to_s # ${1:1:2}
              else
                get_special_var(var_name) || Builtins.get_var(var_name) || ''
              end
      offset = __slice_index(offset)
      offset += value.length if offset < 0
      return '' if offset < 0 || offset > value.length
      return value[offset..] if length.nil?

      length = __slice_index(length)
      (length < 0 ? value[offset...(value.length + length)] : value[offset, length]) || ''
    end

    def __slice_index(expr)
      expr.is_a?(Integer) ? expr : eval_arithmetic_expr(expr.to_s).to_i
    end

    # ${arr[@]:offset[:length]} and ${@:offset[:length]} as a list of
    # elements. For the positional parameters $0 occupies position 0, as in
    # bash, so `${@:1}` is all of them.
    def __array_slice_values(name, offset, length)
      name = Builtins.array_name(name)
      if name == '@' || name == '*'
        values = [respond_to?(:script_name) ? script_name.to_s : 'rubish'] + (positional_params || [])
        offset = __slice_index(offset)
        offset += values.length if offset < 0
        return [] if offset < 0 || offset > values.length

        rest = values[offset..] || []
      elsif Builtins.indexed_array?(name) && !get_special_array_values(name)
        # The offset is an index: `arr=([3]=x [7]=y); ${arr[@]:4}` is y (bash)
        pairs = Builtins.get_array(name).each_with_index.reject { |v, _| v.nil? }
        offset = __slice_index(offset)
        offset += (pairs.last&.last || -1) + 1 if offset < 0
        return [] if offset < 0

        rest = pairs.select { |_, i| i >= offset }.map(&:first)
      else
        values = __array_values(name)
        offset = __slice_index(offset)
        offset += values.length if offset < 0
        return [] if offset < 0 || offset > values.length

        rest = values[offset..] || []
      end
      return rest if length.nil?

      length = __slice_index(length)
      # A negative length is an error for an array (bash)
      raise ParameterExpansionError.new("#{length}: substring expression < 0", status: 1) if length < 0

      rest.first(length)
    end

    # Unquoted / "${arr[*]:...}" form: elements joined like ${arr[@]} / ${arr[*]}
    def __array_slice(name, mode, offset, length)
      values = __array_slice_values(name, offset, length)
      mode == '*' ? Builtins.join_by_ifs(values) : values.join(' ')
    end

    # ${var@operator} - transformation operators
    # Q: Quote for reuse as input
    # E: Expand escape sequences like $'...'
    # P: Expand as prompt string (PS1-style)
    # A: Assignment statement form
    # a: Attribute flags
    # U: Uppercase entire value
    # u: Uppercase first character
    # L: Lowercase entire value
    # K: For associative arrays, show key-value pairs
    # ${x@P}: the value as a prompt; promptvars (on by default) then expands
    # the parameters in it, as for PS1
    def __prompt_transform(value)
      text = expand_prompt(value)
      Builtins.shopt_enabled?('promptvars') ? expand_string_content(text, quoted: true) : text
    end

    def __param_transform(var_name, operator)
      # @k: the key/value pairs of @K, unquoted
      if operator == 'k' && var_name =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        name = $1
        pairs = if Builtins.assoc_array?(name)
                  Builtins.get_assoc_array(name).flat_map { |k, v| [k, v] }
                else
                  Builtins.get_array(name).each_with_index.reject { |v, _| v.nil? }.flat_map { |v, i| [i.to_s, v] }
                end
        return pairs.join(' ')
      end
      if operator == 'K' && var_name =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/
        # subscript/value pairs, values quoted, as bash prints them
        name = $1
        pairs = if Builtins.assoc_array?(name)
                  Builtins.get_assoc_array(name).map { |k, v| "#{k} #{v.inspect}" }
                else
                  (Builtins.get_array(name) || []).each_with_index.filter_map { |v, i| "#{i} #{v.inspect}" unless v.nil? }
                end
        # bash ends each pair of an associative array with a space
        return Builtins.assoc_array?(name) ? pairs.map { |pair| "#{pair} " }.join : pairs.join(' ')
      end
      if %w[Q E P U u L].include?(operator) &&
         (words = __each_param_element(var_name) { |scratch| __param_transform(scratch, operator) })
        return words.join(' ')
      end

      value = __param_value(var_name)

      case operator
      when 'Q' then value.nil? ? '' : __shell_quote_value(value)
      when 'E' then value.nil? ? '' : Builtins.process_escape_sequences(value)
      when 'P' then value.nil? ? '' : __prompt_transform(value)
      when 'A'
        # An assignment that recreates the variable: `x='v'`, `declare -i n='3'`
        # when it has attributes, or a compound assignment for an array
        base = var_name.sub(/\[[@*]\]\z/, '')
        if Builtins.array?(base) || Builtins.assoc_array?(base)
          Builtins.array_declaration(base)
        elsif value.nil?
          ''
        else
          flags = Builtins.declaration_flags(var_name)
          assignment = "#{var_name}=#{__param_transform(var_name, 'Q')}"
          flags.empty? ? assignment : "declare -#{flags} #{assignment}"
        end
      when 'a'
        # Every attribute, in bash's order
        attrs = Builtins.var_attributes_of(var_name)
        flags = +''
        flags << 'a' if Builtins.indexed_array?(var_name)
        flags << 'A' if Builtins.assoc_array?(var_name)
        flags << 'i' if attrs.include?(:integer)
        flags << 'n' if attrs.include?(:nameref)
        flags << 'r' if Builtins.readonly?(var_name)
        flags << 't' if attrs.include?(:trace)
        flags << 'x' if Builtins.exported?(var_name)
        flags << 'l' if attrs.include?(:lowercase)
        flags << 'u' if attrs.include?(:uppercase)
        flags
      when 'U' then value&.upcase || ''
      when 'u' then value.nil? || value.empty? ? '' : value[0].upcase + (value[1..] || '')
      when 'L' then value&.downcase || ''
      when 'K' then value.nil? ? "''" : __param_transform(var_name, 'Q')
      when 'k' then value || ''
      else value || ''
      end
    end

    # ${var/pattern/replacement} or ${var//pattern/replacement}
    # /  - replace first occurrence
    # // - replace all occurrences
    # `${arr[@]OP}`, `${arr[*]OP}`, `${@OP}`: the operator applies to every
    # element. Each element is bound to a scratch parameter in turn and the
    # block gets that parameter's name, so the scalar code path does the work.
    # Returns the resulting words, or nil when var_name is not such a reference.
    SCRATCH_PARAM = '__rubish_element'

    def __each_param_element(var_name)
      elements = case var_name
                 when '@', '*' then positional_params || []
                 when /\A([a-zA-Z_][a-zA-Z0-9_]*)\[[@*]\]\z/ then __array_values($1)
                 end
      return nil unless elements

      saved = Builtins.get_var(SCRATCH_PARAM)
      begin
        elements.map do |element|
          Builtins.set_var(SCRATCH_PARAM, element)
          yield SCRATCH_PARAM
        end
      ensure
        saved ? Builtins.set_var(SCRATCH_PARAM, saved) : Builtins.delete_var(SCRATCH_PARAM)
      end
    end

    # The words of "${arr[@]OP}" / "${@OP}": OP applied to each element
    def __param_element_words(name, tail)
      ref = name == '@' ? '@' : "#{name}[@]"
      __each_param_element(ref) { |scratch| expand_parameter_expansion("#{scratch}#{tail}") } || []
    end

    # The value of a parameter for the pattern operators: positional and
    # special parameters included
    def __param_value(var_name)
      get_param_expand_info(var_name).first
    end

    def __param_replace(var_name, operator, pattern, replacement)
      if pattern.start_with?('#')
        position = :prefix
        pattern = pattern[1..]
      elsif pattern.start_with?('%')
        position = :suffix
        pattern = pattern[1..]
      else
        position = :any
      end

      # The pattern and the replacement are words: variables expand in
      # them, and a quoted part of the pattern matches literally
      __param_replace_with(var_name, operator, position, __expand_pattern_word(pattern), __expand_replacement_word(replacement))
    end

    def __param_replace_with(var_name, operator, position, pattern, replacement)
      if (words = __each_param_element(var_name) { |scratch| __param_replace_with(scratch, operator, position, pattern, replacement) })
        return words.join(' ')
      end

      value = __param_value(var_name) || ''
      return '' if value.empty?

      regex = pattern_to_regex(pattern, position, :longest)
      replacement_proc = build_replacement_proc(replacement)

      case operator
      when '//' then replacement_proc ? value.gsub(regex, &replacement_proc) : value.gsub(regex, replacement)
      when '/' then replacement_proc ? value.sub(regex, &replacement_proc) : value.sub(regex, replacement)
      else value
      end
    end

    # Expand a word used as a pattern: an unquoted part expands and keeps
    # its pattern characters, a quoted part is matched literally
    def __expand_pattern_word(word)
      result = +''
      WordSegments.each_segment(word) do |type, content|
        result << case type
                  when :single then __quote_pattern(content)
                  when :ansi_c then __quote_pattern(Builtins.process_escape_sequences(content))
                  when :double then __quote_pattern(expand_string_content(content, quoted: true))
                  when :bare then expand_string_content(content)
                  end
      end
      result
    end

    # Expand the replacement word: a quoted `&` is literal, an unquoted one
    # stands for the match under patsub_replacement, and `\&` stays for the
    # replacement to read
    def __expand_replacement_word(word)
      result = +''
      WordSegments.each_segment(word) do |type, content|
        result << case type
                  when :single then content.gsub('&') { '\\&' }
                  when :ansi_c then Builtins.process_escape_sequences(content).gsub('&') { '\\&' }
                  when :double then expand_string_content(content, quoted: true).gsub('&') { '\\&' }
                  when :bare then content.split(/(\\&)/).map { |part| part == '\\&' ? part : expand_string_content(part) }.join
                  end
      end
      result
    end

    def __quote_pattern(text)
      text.gsub(/[*?\[\]\\]/) { |c| "\\#{c}" }
    end

    ANSI_C_ESCAPES = { "\a" => '\a', "\b" => '\b', "\e" => '\E', "\f" => '\f', "\n" => '\n', "\r" => '\r', "\t" => '\t', "\v" => '\v', '\\' => '\\\\', "'" => "\\'" }.freeze

    # ${var@Q}: single quotes, or $'...' when the value has control
    # characters (bash)
    def __shell_quote_value(value)
      if value.match?(/[\x00-\x1f\x7f]/)
        escaped = value.gsub(/[\x00-\x1f\x7f\\']/) { |c| ANSI_C_ESCAPES[c] || format('\\%03o', c.ord) }
        "$'#{escaped}'"
      else
        "'" + value.gsub("'") { "'\\''" } + "'"
      end
    end

    # Case modification operators
    # ^  - uppercase first character (if matches pattern)
    # ^^ - uppercase all characters (matching pattern)
    # ,  - lowercase first character (if matches pattern)
    # ,, - lowercase all characters (matching pattern)
    def __param_case(var_name, operator, pattern)
      if (words = __each_param_element(var_name) { |scratch| __param_case(scratch, operator, pattern) })
        return words.join(' ')
      end

      value = __param_value(var_name) || ''
      return '' if value.empty?

      case operator
      when '^^' then apply_case_transform(value, pattern, :upcase, :all)
      when '^' then apply_case_transform(value, pattern, :upcase, :first)
      when '~~' then apply_case_transform(value, pattern, :swapcase, :all)
      when '~' then apply_case_transform(value, pattern, :swapcase, :first)
      when ',,' then apply_case_transform(value, pattern, :downcase, :all)
      when ',' then apply_case_transform(value, pattern, :downcase, :first)
      else value
      end
    end

    # ${!var} - indirect expansion: get value of variable whose name is in var
    # ${!prefix*} / ${!prefix@}: names of all variables starting with prefix,
    # sorted; as one IFS-joined word for *, one word per name for @
    def __var_names_with_prefix(prefix)
      (Builtins.shell_var_names + ENV.keys).uniq.select { |k| k.start_with?(prefix) }.sort
    end

    def __param_indirect(var_name)
      # ${!#}: the last positional parameter
      return (positional_params.last || '') if var_name == '#'

      # ${!ref} of a nameref gives the name it refers to (bash)
      return Builtins.resolve_nameref(var_name) || '' if Builtins.nameref?(var_name)

      indirect_name = Builtins.get_var(var_name)
      return '' if indirect_name.nil? || indirect_name.empty?
      # A number names a positional parameter: `${!OPTIND}` is `$3` when OPTIND is 3
      return (positional_params[indirect_name.to_i - 1] || '') if indirect_name.match?(/\A[1-9][0-9]*\z/)

      Builtins.get_var(indirect_name) || ''
    end

    # ${!name<op>...}: expand indirectly through name, then apply the
    # operator to the parameter it names (`${!n:-def}`, `${!n#pat}`)
    def __param_indirect_rest(var_name, rest)
      target = Builtins.nameref?(var_name) ? Builtins.resolve_nameref(var_name).to_s : Builtins.get_var(var_name).to_s
      return '' unless target.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*(\[[^\]]*\])?\z/)

      expand_parameter_expansion("#{target}#{rest}")
    end

    # $"string" - locale-specific translation using TEXTDOMAIN
    # Uses gettext if available, otherwise returns original string
    def __translate(string)
      # noexpand_translation: do not expand $"..." strings for translation
      return string if Builtins.shopt_enabled?('noexpand_translation')

      textdomain = ENV['TEXTDOMAIN']
      return string if textdomain.nil? || textdomain.empty?

      begin
        require 'gettext'
        textdomaindir = ENV['TEXTDOMAINDIR']
        textdomaindir && !textdomaindir.empty? ? GetText.bindtextdomain(textdomain, path: textdomaindir) : GetText.bindtextdomain(textdomain)
        GetText._(string)
      rescue LoadError, StandardError
        string
      end
    end

    # ${arr[n]} or ${map[key]} - get array/assoc element
    # For associative arrays, index is expanded as string (key lookup)
    # For indexed arrays, index is evaluated as arithmetic expression
    def __array_element(var_name, index)
      var_name = Builtins.array_name(var_name)
      expanded_index = expand_array_index(var_name, index)

      # Check special arrays first
      values = get_special_array_values(var_name)
      if values
        return get_special_assoc_value(var_name, expanded_index) if values == :assoc
        idx = safe_eval_index(expanded_index)
        return (values[idx] || '').to_s
      end

      if Builtins.assoc_array?(var_name)
        if Builtins.set_option?('u') && !Builtins.get_assoc_array(var_name).key?(expanded_index)
          $stderr.puts Builtins.format_error('unbound variable', command: "#{var_name}[#{expanded_index}]")
          raise NounsetError, "#{var_name}[#{expanded_index}]: unbound variable"
        end
        Builtins.get_assoc_element(var_name, expanded_index)
      else
        Builtins.get_array_element(var_name, safe_eval_index(expanded_index))
      end
    end

    # Build the words for a double-quoted word containing "${arr[@]}".
    # pieces holds expanded text Strings and element Arrays, in order. Text
    # attaches to the neighbouring elements, so with arr=(1 2) the word
    # "x${arr[@]}y" becomes ["x1", "2y"]. A word made only of empty
    # expansions disappears, like "$@" with no positional parameters.
    def __quoted_array_words(pieces)
      words = [+'']
      literal_text = false
      pieces.each do |piece|
        if piece.is_a?(Array)
          next if piece.empty?
          words[-1] << piece[0].to_s
          words.concat(piece[1..].map { |e| e.to_s.dup })
        else
          literal_text ||= !piece.empty?
          words[-1] << piece
        end
      end
      words == [''] && !literal_text ? [] : words
    end

    # ${arr[@]} or ${arr[*]} - get all array/assoc values
    # @ mode: elements joined by space
    # * mode: elements joined by first character of IFS
    def __array_all(var_name, mode)
      values = __array_values(var_name)
      mode == '@' ? values.join(' ') : Builtins.join_by_ifs(values)
    end

    # Raw element list for `${arr[@]}` / `${arr[*]}` — used by the
    # array-literal codegen path (`arr=(${other[@]})`) where unquoted
    # array expansion must word-split into separate elements rather
    # than collapse to a single string. Handles both regular arrays
    # and special arrays (PIPESTATUS / pipestatus, GROUPS, FUNCNAME, …).
    def __array_values(var_name)
      return (positional_params || []).map(&:to_s) if var_name == '@' || var_name == '*'

      var_name = Builtins.array_name(var_name)
      values = get_special_array_values(var_name)
      case values
      when Array then values.map(&:to_s)
      when :assoc then get_special_assoc_all_values(var_name)
      when nil
        if Builtins.assoc_array?(var_name)
          Builtins.assoc_values(var_name)
        else
          Builtins.get_array(var_name).compact
        end
      else values
      end
    end

    # ${#arr[@]} - get array/assoc length
    def __array_length(var_name)
      var_name = Builtins.array_name(var_name)
      if Builtins.set_option?('u') && !Builtins.array?(var_name) && !Builtins.assoc_array?(var_name) && !Builtins.var_set?(var_name) && get_special_array_values(var_name).nil?
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      values = get_special_array_values(var_name)
      length = case values
               when Array then values.length
               when :assoc then get_special_assoc_length(var_name)
               when nil
                 Builtins.assoc_array?(var_name) ? Builtins.assoc_length(var_name) : Builtins.array_length(var_name)
               else values.length
               end
      length.to_s
    end

    # ${!arr[@]} - get array indices or assoc keys
    def __array_keys(var_name, mode = '@')
      keys = __array_key_list(var_name)
      mode == '*' ? Builtins.join_by_ifs(keys) : keys.join(' ')
    end

    # Indices (indexed arrays) or keys (associative arrays) as an Array of
    # strings — the per-word form of ${!arr[@]} used by "${!arr[@]}".
    def __array_key_list(var_name)
      var_name = Builtins.array_name(var_name)
      values = get_special_array_values(var_name)
      keys = case values
             when Array then (0...values.length).to_a
             when :assoc then get_special_assoc_keys(var_name)
             when nil
               if Builtins.assoc_array?(var_name)
                 Builtins.assoc_keys(var_name)
               else
                 arr = Builtins.get_array(var_name)
                 arr.each_index.select { |i| !arr[i].nil? }
               end
             else (0...values.length).to_a
             end
      keys.map(&:to_s)
    end

    # === REPL methods ===

    # One element of a pipeline. An expansion error in it ends only that
    # element, as bash runs each in a subshell: the error is reported and a
    # failing command stands in for it
    def __pipe_elem
      yield
    rescue ArithmeticEvaluator::Error, ParameterExpansionError => e
      $stderr.puts "rubish: #{e.message}"
      Command.new('false')
    rescue NounsetError, FailglobError
      Command.new('false')
    end

    def __cmd(name, *args, __prefix_env: nil, &block)
      cmd = Command.new(name, *args, &block)
      cmd.prefix_env = __prefix_env if __prefix_env
      cmd
    end

    # `$cmd args` with an unquoted expansion as the command: its words are
    # split, the first is the command. An empty expansion alone runs
    # nothing; `$empty cmd` runs cmd (bash)
    def __cmd_from_words(value, args, __prefix_env: nil, &block)
      words = Builtins.split_by_ifs(value.to_s)
      if words.empty?
        return ExitStatus.new(0) if args.empty?

        words = [args.shift]
      end
      __cmd(words.first, *words[1..], *args, __prefix_env: __prefix_env, &block)
    end

    def __and_cmd(left_proc, right_proc)
      # Per POSIX: all commands in an AND-OR list except the last are exempt from errexit.
      # Restore the flag in an ensure so an exception escaping the left operand
      # (set -u, failglob, a host syscall error) can't leave it stuck on and
      # silently mask the next failing command.
      prev = @errexit_suppressed
      @errexit_suppressed = true
      begin
        left = __run_cmd(&left_proc)
      ensure
        @errexit_suppressed = prev
      end
      unless @last_status == 0
        # Left failed -> && short-circuits; its status stays exempt from errexit.
        @errexit_exempt = true
        return left
      end

      __run_cmd(&right_proc)
    end

    def __or_cmd(left_proc, right_proc)
      # Per POSIX: all commands in an AND-OR list except the last are exempt from errexit.
      # Restore the flag in an ensure so an exception escaping the left operand
      # (set -u, failglob, a host syscall error) can't leave it stuck on and
      # silently mask the next failing command.
      prev = @errexit_suppressed
      @errexit_suppressed = true
      begin
        left = __run_cmd(&left_proc)
      ensure
        @errexit_suppressed = prev
      end
      return left if @last_status == 0

      __run_cmd(&right_proc)
    end

    def __background(text = nil, &block)
      # Wait if CHILD_MAX limit is reached
      JobManager.instance.wait_for_child_slot if Builtins.set_option?('m')

      # Fork and run in background
      pid = fork do
        # Reset signal handlers in child
        @proc_sub_fds = nil # the parent owns the pipe ends it keeps
        Kernel.trap('INT', 'DEFAULT')
        Kernel.trap('TSTP', 'DEFAULT')

        # Create new process group if job control is enabled, then run the
        # job without job control: its commands must not take the terminal
        if Builtins.set_option?('m')
          Process.setpgid(0, 0)
          Builtins.disable_job_control
        end

        # Execute the command. `exit N` inside the job ends only the job,
        # and the job's exit status is the command's, so `wait $!` sees it.
        exited = true
        result = catch(:exit) do
          value = block.call
          exited = false
          value
        end
        Kernel.exit(result || @last_status || 0) if exited
        result.run if result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell)
        Kernel.exit(Subshell.exit_code_for(result))
      end

      @last_bg_pid = pid

      # Every background job is tracked, so that `jobs`, `wait -n` and
      # `%1` work in scripts too; its own process group only with job control
      Process.setpgid(pid, pid) rescue nil if Builtins.set_option?('m') # May fail if child already set it
      job = JobManager.instance.add(
        pid: pid,
        pgid: pid,
        command: text || @current_line || @last_line # the job's own text, as jobs lists it
      )
      # The notice is for interactive shells only, as in bash
      puts "[#{job.id}] #{pid}" if Builtins.interactive_mode?
      nil
    end

    # Handle {varname} redirection syntax: exec {fd}>file
    # Allocates a file descriptor >= 10 and stores it in the named variable
    def __varname_redirect(varname, operator, target, &block)
      # `{var}>&-` closes the descriptor the variable holds
      if %w[>& <&].include?(operator) && target == '-'
        close_fd_by_number(Builtins.get_var(varname).to_i)
        return block.call
      end

      # Allocate a new FD number (>= 10, avoiding conflicts)
      fd_num = allocate_varname_fd

      # Store the FD number in the variable
      Builtins.set_var(varname, fd_num.to_s)

      # Track this FD for potential auto-closing
      @varname_fds[varname] = {fd: fd_num, target: target, operator: operator}

      # Now perform the actual redirection
      case operator
      when '>'
        # Open file for writing, associate with fd_num
        io = File.open(expand_single_arg(target), 'w')
        perform_varname_redirect(fd_num, io, &block)
      when '>>'
        # Open file for appending
        io = File.open(expand_single_arg(target), 'a')
        perform_varname_redirect(fd_num, io, &block)
      when '<'
        # Open file for reading
        io = File.open(expand_single_arg(target), 'r')
        perform_varname_redirect(fd_num, io, &block)
      when '<<<'
        # `{fd}<<< word`: the word, with a newline, readable from the descriptor
        io = Command.content_file("#{expand_single_arg(target)}\n")
        perform_varname_redirect(fd_num, io, &block)
      when '>&'
        # Duplicate output FD
        src_fd = target.to_i
        perform_fd_dup(fd_num, src_fd, &block)
      when '<&'
        # Duplicate input FD
        src_fd = target.to_i
        perform_fd_dup(fd_num, src_fd, &block)
      else
        block.call
      end
    ensure
      # If varredir_close is enabled, close the FD after command completes
      if Builtins.shopt_enabled?('varredir_close') && @varname_fds[varname]
        close_varname_fd(varname)
      end
    end

    # Redirect output for compound commands (loops, conditionals, etc.)
    # `(if/while/for/...) N>file` for N >= 3. Compound commands run
    # in-process so we'd need to dup the fd at the Ruby level — not
    # wired up yet. Yield silently for now; the redirect is dropped.
    # `{var}>&N` / `{var}<&N`: the new descriptor is a copy of N
    def perform_fd_dup(fd_num, src_fd, &block)
      source = Command.standard_or_shell_fd(src_fd)
      unless source.is_a?(IO) && !source.closed?
        $stderr.puts "rubish: #{src_fd}: Bad file descriptor"
        @varname_fds.delete_if { |_, info| info[:fd] == fd_num }
        return false
      end

      perform_varname_redirect(fd_num, source.dup, &block)
    end

    def close_varname_fd(varname)
      info = @varname_fds.delete(varname)
      return unless info

      @state.shell_fds.delete(info[:fd])
      info[:io].close if info[:io] && !info[:io].closed?
    end

    # Close a descriptor by number: one allocated for a {var} redirection,
    # or one opened with `exec N>file`
    def close_fd_by_number(fd_num)
      name, = @varname_fds.find { |_, info| info[:fd] == fd_num }
      return close_varname_fd(name) if name

      io = @state.shell_fds.delete(fd_num)
      io.close if io.is_a?(IO) && !io.closed?
    end

    # `while ...; done 3< file`, `{ ...; } 4<<< word`: descriptor N is set
    # up for the duration of the compound command, then closed, and what
    # it was before is put back. A redirection that fails ends the command
    # with status 1 without running it, as in bash.
    def __with_fd_redirect(fd, op, target)
      previous = shell_fds.delete(fd)
      spec = Command.fd_redirect_spec(op, target)
      unless apply_fd_redirect_spec(fd, spec)
        shell_fds[fd] = previous if previous
        return ExitStatus.new(1)
      end

      begin
        yield
      ensure
        shell_fds.delete(fd)&.close
        shell_fds[fd] = previous if previous
      end
    end

    def __with_redirect(operator, target)
      case operator
      when '>'
        # Check noclobber: if set and file exists, fail
        if Builtins.set_option?('C') && File.file?(target)
          $stderr.puts "rubish: #{target}: cannot overwrite existing file"
          return ExitStatus.new(1)
        end
        __with_stdout_redirect(target, 'w') { yield }
      when '>|'
        # Force overwrite even with noclobber
        __with_stdout_redirect(target, 'w') { yield }
      when '>>'
        __with_stdout_redirect(target, 'a') { yield }
      when '<'
        __with_stdin_redirect(target) { yield }
      when '<>'
        __with_stdin_redirect(target, File::RDWR | File::CREAT) { yield }
      when '2>'
        __with_stderr_redirect(target) { yield }
      when '2>>'
        __with_stderr_redirect(target, 'a') { yield }
      when '&>', '&>>'
        # Both streams to the file (bash)
        __with_stdout_redirect(target, operator == '&>' ? 'w' : 'a') { __with_dup_redirect('2>&', '1') { yield } }
      when '>&', '2>&', '<&'
        __with_dup_redirect(operator, target) { yield }
      else
        yield
      end
    end

    # `>&N`, `2>&N` and `<&N` on a compound command: for the block, point the
    # shell's stream at the stream (or `exec N>file` descriptor) N names, as
    # it is at this point in the redirection list. `>& file` sends both
    # stdout and stderr to the file.
    def __with_dup_redirect(operator, target)
      unless target.match?(/\A\d+\z/)
        return yield unless operator == '>&' && target != '-'

        return __with_stdout_redirect(target, 'w') { __with_dup_redirect('2>&', '1') { yield } }
      end

      io = Command.standard_or_shell_fd(target.to_i)
      unless io
        $stderr.puts "rubish: #{target}: Bad file descriptor"
        return ExitStatus.new(1)
      end

      if operator == '<&'
        old = $stdin
        begin
          $stdin = io
          yield
        ensure
          $stdin = old
        end
      else
        __with_dup_output_stream(operator == '>&' ? :stdout : :stderr, io) { yield }
      end
    end

    # The stream gets a copy of the descriptor, as dup(2) would give it: an
    # alias of the same IO object would follow that object when a later
    # redirection, or a child process pointing its real fds at the shell's
    # streams, reopens it (`{ ...; } 2>&1 >/dev/null` must keep stderr on
    # the original stdout).
    def __with_dup_output_stream(stream, io)
      io.flush if io.respond_to?(:flush)
      copy = io.dup
      copy.sync = true
      old = stream == :stdout ? $stdout : $stderr
      begin
        stream == :stdout ? $stdout = copy : $stderr = copy
        yield
      ensure
        stream == :stdout ? $stdout = old : $stderr = old
        copy.close unless copy.closed?
      end
    end

    # Open a compound command's redirection target. A target that cannot be
    # opened is reported and the command is skipped with status 1, as for a
    # simple command
    def __open_redirect_target(file, mode)
      File.open(file, mode)
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      nil
    end
    
    def __with_stdout_redirect(file, mode)
      io = __open_redirect_target(file, mode) or return ExitStatus.new(1)
      old_stdout = $stdout
      begin
        $stdout = io
        yield
      ensure
        $stdout.close unless $stdout == old_stdout || $stdout.closed?
        $stdout = old_stdout
      end
    end

    def __with_stdin_redirect(file, mode = 'r')
      io = __open_redirect_target(file, mode) or return ExitStatus.new(1)
      old_stdin = $stdin
      begin
        $stdin = io
        yield
      ensure
        $stdin.close unless $stdin == old_stdin || $stdin.closed?
        $stdin = old_stdin
      end
    end

    def __with_stderr_redirect(file, mode = 'w')
      io = __open_redirect_target(file, mode) or return ExitStatus.new(1)
      old_stderr = $stderr
      begin
        $stderr = io
        yield
      ensure
        $stderr.close unless $stderr == old_stderr || $stderr.closed?
        $stderr = old_stderr
      end
    end

    def __condition(&block)
      # A condition is exempt from errexit all the way down: a function
      # called here may fail inside and go on (bash)
      prev = @errexit_suppressed
      @errexit_suppressed = true
      __evaluate_condition(&block)
    ensure
      @errexit_suppressed = prev
    end

    def __evaluate_condition(&block)
      @last_subst_status = nil
      result = block.call
      # The condition is a command like any other to set -x
      announce_command(result) if result.is_a?(Command) || result.is_a?(Pipeline)
      if __bare_assignment_command?(result)
        # `if x=$(cmd); then` tests the substitution's status
        __run_bare_assignment(result) == 0
      elsif result.is_a?(Command) && Command.function?(result.name)
        # `if myfunc; then`: call the function here, not in a fork
        status = call_function_with_redirects(result)
        status.respond_to?(:success?) ? status.success? : @last_status == 0
      elsif result.is_a?(Command) && Builtins.builtin?(result.name)
        # Run builtin directly and check its return value
        run_builtin_with_prefix(result)
      else
        # `if (cmd); then`: a subshell is run here too
        result.run if result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell)
        result.success?
      end
    end

    def __ruby_condition(expression)
      # Evaluate Ruby expression with shell variables bound as locals
      # VAR=foo becomes var = 'foo' in the Ruby binding
      # Use __binding__ to avoid conflicts with shell variable names
      __binding__ = binding
      __bound_vars__ = Set.new

      # First bind shell variables (these take precedence, includes function-local vars)
      Builtins.current_state.shell_vars.each do |key, value|
        var_name = key.downcase
        next unless var_name =~ /\A[a-z_][a-z0-9_]*\z/
        __binding__.local_variable_set(var_name.to_sym, value)
        __bound_vars__ << var_name
      end

      # Then bind ENV variables (inherited environment, unless already bound from shell_vars)
      ENV.each do |key, value|
        var_name = key.downcase
        next unless var_name =~ /\A[a-z_][a-z0-9_]*\z/
        next if __bound_vars__.include?(var_name)
        __binding__.local_variable_set(var_name.to_sym, value)
      end

      __binding__.eval(expression)
    end

    # Count loop nesting, so break and continue know whether a loop encloses
    # them (a function body starts the count afresh, as in bash)
    def __in_loop
      Builtins.loop_depth += 1
      yield
    ensure
      Builtins.loop_depth -= 1
    end

    def __for_loop(variable, items, &block)
      items.each do |item|
        Builtins.set_var(variable, item)
        block.call
      end
    end

    def __each_loop(variable, source_lambda, body_code, &block)
      # Each loop: cmd.each {|var| body }
      # Captures output from source command and iterates over each line
      read_io, write_io = IO.pipe

      pid = fork do
        read_io.close
        $stdout.reopen(write_io)
        write_io.close

        # Call the lambda which creates a Command/Pipeline object
        result = source_lambda.call

        # Run the command if it's a Command or Pipeline
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)

        Kernel.exit(0)
      end

      write_io.close

      # Read output line by line and yield to block
      read_io.each_line do |line|
        block.call(line.chomp)
      end

      read_io.close
      Process.wait(pid)
    end

    def __eval_shell_code(code_string)
      # Parse and execute shell code string
      return if code_string.nil? || code_string.empty?

      tokens = Lexer.new(code_string).tokenize
      return if tokens.empty?

      ast = Parser.new(tokens).parse
      return unless ast

      code = Codegen.new.generate(ast)
      eval_in_context(code)
    end

    def __select_loop(variable, items, &block)
      return if items.empty?

      # Display menu once at start
      display_select_menu(items)

      loop do
        # Get PS3 prompt (default "#? ")
        # PS3 supports the same escape sequences as PS1
        ps3 = ENV['PS3'] || '#? '
        expanded_prompt = expand_prompt(ps3)
        $stderr.print expanded_prompt

        # Read user input
        reply = $stdin.gets
        break unless reply  # EOF

        reply = reply.chomp
        Builtins.set_var('REPLY', reply)

        # Parse selection
        if reply =~ /\A\d+\z/
          num = reply.to_i
          if num >= 1 && num <= items.length
            Builtins.set_var(variable, items[num - 1])
          else
            Builtins.set_var(variable, '')
          end
        else
          Builtins.set_var(variable, '')
        end

        # Execute body
        block.call
      end
    end

    def __fetch_var(var_name)
      return (Builtins.get_var(var_name) || '').to_s if Builtins.current_state.unset_special_vars.include?(var_name)

      # Special handling for SECONDS, RANDOM, LINENO, PPID, UID, EUID, GROUPS, HOSTNAME, RUBISHPID, BASHPID, HISTCMD, and EPOCHSECONDS
      return (@funcname_stack || []).first.to_s if var_name == 'FUNCNAME'
      return (@pipestatus || []).first.to_s if var_name == 'PIPESTATUS' # $PIPESTATUS is its first element
      return get_special_array_values(var_name).first.to_s if var_name == 'BASH_SOURCE' || var_name == 'RUBISH_SOURCE'
      return seconds.to_s if var_name == 'SECONDS'
      return random.to_s if var_name == 'RANDOM'
      return @lineno.to_s if var_name == 'LINENO'
      return Process.ppid.to_s if var_name == 'PPID'
      return Process.uid.to_s if var_name == 'UID'
      return Process.euid.to_s if var_name == 'EUID'
      return (Process.groups.first || '').to_s if var_name == 'GROUPS'
      return Socket.gethostname if var_name == 'HOSTNAME'
      return Process.pid.to_s if var_name == 'RUBISHPID'
      return Process.pid.to_s if var_name == 'BASHPID'
      return @command_number.to_s if var_name == 'HISTCMD'
      return Time.now.to_i.to_s if var_name == 'EPOCHSECONDS'
      return format('%.6f', Time.now.to_f) if var_name == 'EPOCHREALTIME'
      return SecureRandom.random_number(2**32).to_s if var_name == 'SRANDOM'
      return monoseconds.to_s if var_name == 'RUBISH_MONOSECONDS' || var_name == 'BASH_MONOSECONDS'
      return argv0 if var_name == 'BASH_ARGV0' && !@bash_argv0_unset
      return Rubish::VERSION if var_name == 'RUBISH_VERSION'
      return Rubish::VERSION if var_name == 'BASH_VERSION'
      return ostype if var_name == 'OSTYPE'
      return hosttype if var_name == 'HOSTTYPE'
      return RUBY_PLATFORM if var_name == 'MACHTYPE'
      return @state.bash_command if var_name == 'RUBISH_COMMAND'
      return @state.bash_command if var_name == 'BASH_COMMAND'
      return Builtins.subshell_level.to_s if var_name == 'RUBISH_SUBSHELL' || var_name == 'BASH_SUBSHELL'
      return terminal_columns.to_s if var_name == 'COLUMNS'
      return terminal_lines.to_s if var_name == 'LINES'
      return Builtins.comp_line if var_name == 'COMP_LINE'
      return Builtins.comp_point.to_s if var_name == 'COMP_POINT'
      return Builtins.comp_cword.to_s if var_name == 'COMP_CWORD'
      return Builtins.comp_type.to_s if var_name == 'COMP_TYPE'
      return Builtins.comp_key.to_s if var_name == 'COMP_KEY'
      return Builtins.comp_wordbreaks if var_name == 'COMP_WORDBREAKS'
      return Builtins.bashopts if var_name == 'BASHOPTS'
      return Builtins.bash_compat if var_name == 'BASH_COMPAT'
      return ENV['RUBISH_EXECUTION_STRING'] || '' if var_name == 'RUBISH_EXECUTION_STRING' || var_name == 'BASH_EXECUTION_STRING'
      return rubish_path if var_name == 'RUBISH' || var_name == 'BASH'
      return Builtins.current_state.current_trapsig || '' if var_name == 'RUBISH_TRAPSIG' || var_name == 'BASH_TRAPSIG'
      return Builtins.readline_line if var_name == 'READLINE_LINE'
      return Builtins.readline_point.to_s if var_name == 'READLINE_POINT'
      return Builtins.readline_mark.to_s if var_name == 'READLINE_MARK'

      # Check if it's an array variable - join with space for string context
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name).join(' ')
      end

      # Fetch variable with nounset check
      if Builtins.set_option?('u') && !Builtins.var_set?(var_name)
        $stderr.puts Builtins.format_error('unbound variable', command: var_name)
        raise NounsetError, "#{var_name}: unbound variable"
      end
      Builtins.get_var(var_name) || ''
    end

    # Fetch variable for use as command argument (quoted context)
    # Returns array if variable is an array (for proper expansion)
    # Returns string otherwise (empty string is preserved as "$var" keeps empty strings)
    def __fetch_var_for_arg(var_name)
      # Check if it's an array variable first
      if Builtins.array?(var_name)
        return Builtins.get_array(var_name)
      end

      # Otherwise fetch as regular variable
      __fetch_var(var_name)
    end

    # Fetch variable for use as command argument (unquoted context)
    # In bash, unquoted empty variable expansion is removed by word splitting
    # e.g., `cat $empty_var` becomes `cat` (no arguments), not `cat ""`
    # Returns array for proper flatten behavior - empty array if value is empty
    def __fetch_var_for_arg_unquoted(var_name)
      # Check if it's an array variable first
      if Builtins.array?(var_name)
        arr = Builtins.get_array(var_name)
        # Filter out empty strings from array expansion too
        return arr.reject(&:empty?)
      end

      # Otherwise fetch as regular variable and word-split by IFS.
      # With shwordsplit unset (zsh behavior, opted into via `unsetopt
      # shwordsplit`), the scalar stays one word — though an empty
      # expansion is still removed, as in zsh.
      value = __fetch_var(var_name)
      return [] if value.nil?
      unless Builtins.zsh_option_enabled?('sh_word_split')
        return value.empty? ? [] : [value]
      end
      # Each word is a pattern: `x='*.txt'; echo $x` lists the files (bash)
      Builtins.split_by_ifs(value).flat_map { |w| w.match?(/[*?\[]/) ? __glob(w) : [w] }
    end

    # Word-split the result of a standalone unquoted ${...} expansion and
    # glob each resulting word — the same treatment the builtin fast path
    # gives it in expand_single_arg_with_brace_and_glob. always_split is
    # true for array expansions (${arr[@]} and friends), which split
    # regardless of shwordsplit; scalars honor the option.
    def __split_unquoted_expansion(value, always_split)
      value = value.to_s
      words = if always_split || Builtins.zsh_option_enabled?('sh_word_split')
                Builtins.split_by_ifs(value)
              else
                value.empty? ? [] : [value]
              end
      words.flat_map { |w| w.match?(/[*?\[]|[+@!]\(/) ? __glob(w) : [w] }
    end

    def __glob(pattern)
      # If noglob is set, return pattern as-is (no expansion)
      return [pattern] if Builtins.set_option?('f')

      # Handle VAR="value" or VAR='value' patterns: strip quotes from value
      # This is needed for commands like: env VAR="value" cmd
      if pattern =~ /\A([a-zA-Z_][a-zA-Z0-9_]*)=(["'])(.*)\2\z/
        var_name = $1
        value = $3
        return ["#{var_name}=#{value}"]
      end

      # Handle globstar: ** matches directories recursively only when enabled
      # When disabled, treat ** as * (non-recursive)
      glob_pattern = if pattern.include?('**') && !Builtins.shopt_enabled?('globstar')
                       pattern.gsub('**', '*')
                     elsif pattern.end_with?('**')
                       # A final `**` names everything below (bash); Ruby's would
                       # act like `*`. `dir/**` also matches `dir/` itself.
                       "#{pattern}/*"
                     else
                       pattern
                     end

      # globasciiranges: when disabled, expand letter ranges to include both cases
      # (approximates locale-aware collation where a-z might include A-Z)
      unless Builtins.shopt_enabled?('globasciiranges')
        glob_pattern = expand_locale_ranges(glob_pattern)
      end

      # Expand POSIX character classes (e.g., [[:digit:]] -> [0-9])
      glob_pattern = expand_posix_classes(glob_pattern)

      # Expand glob pattern, return original if no matches (unless nullglob)
      # Check for extended globs if extglob is enabled
      # Build glob flags based on options
      glob_flags = 0
      glob_flags |= File::FNM_DOTMATCH if Builtins.shopt_enabled?('dotglob')
      glob_flags |= File::FNM_CASEFOLD if Builtins.shopt_enabled?('nocaseglob')

      if Builtins.shopt_enabled?('extglob') && has_extglob?(glob_pattern)
        matches = expand_extglob(glob_pattern)
      else
        globstar_self = pattern[/\A(.+\/)\*\*\z/, 1] if Builtins.shopt_enabled?('globstar')
        matches = Dir.glob(glob_pattern, glob_flags)
        # Ruby's glob folds case on a case-insensitive filesystem (macOS);
        # bash matches names as written unless nocaseglob is on
        unless Builtins.shopt_enabled?('nocaseglob')
          matches.select! { |m| File.fnmatch?(glob_pattern, m, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) }
        end
        matches.unshift(globstar_self) if globstar_self && File.directory?(globstar_self)
      end

      # Filter out . and .. when dotglob is enabled or globskipdots is set
      if Builtins.shopt_enabled?('dotglob') || Builtins.shopt_enabled?('globskipdots')
        matches = matches.reject { |m| m.end_with?('/.') || m.end_with?('/..') || m == '.' || m == '..' }
      end

      # Apply GLOBIGNORE filtering
      matches = apply_globignore(matches)

      # Apply GLOBSORT sorting
      matches = apply_globsort(matches)

      if matches.empty?
        # Try abbreviated path expansion: l/r/repl.rb -> lib/rubish/repl.rb
        if pattern.include?('/') && !pattern.match?(/[*?\[\]]/)
          expanded = expand_abbreviated_path(pattern)
          return [expanded] if expanded && File.exist?(expanded)
        end

        # A word without pattern characters is not a pattern: nullglob and
        # failglob leave it alone (bash)
        glob_chars = pattern.match?(/[*?\[]|[+@!]\(/)
        if Builtins.shopt_enabled?('failglob') && glob_chars
          # failglob: patterns matching nothing cause an error
          $stderr.puts Builtins.format_error("no match: #{pattern}")
          raise FailglobError, "no match: #{pattern}"
        elsif Builtins.shopt_enabled?('nullglob') && glob_chars
          # nullglob: patterns matching nothing expand to nothing
          []
        else
          # The word stays as written, minus the backslashes that quoted its
          # glob characters: `echo \*` prints *
          [pattern.gsub(/\\(.)/, '\1')]
        end
      else
        matches
      end
    end

    # Close the pipe ends kept open for process substitutions, from the
    # given position in the list on. The command they were made for is
    # over; a child that runs or uses the substitution has its own copy.
    def cleanup_proc_subs(from = 0)
      return unless @proc_sub_fds

      @proc_sub_fds.slice!(from..).each do |io|
        io.close unless io.closed?
      rescue SystemCallError
        # Already gone
      end
    end

    # Run a command's block; the process substitutions it makes are closed
    # once it is over, as bash closes them after each command
    def __closing_proc_subs
      mark = @proc_sub_fds ? @proc_sub_fds.size : 0
      yield
    ensure
      cleanup_proc_subs(mark)
    end

    # Process substitution: `<(cmd)` or `>(cmd)` expands to the /dev/fd/N
    # path of a pipe, as in bash. The command runs in a child writing to
    # (or reading from) the pipe's other end. The shell keeps this end open
    # until the command it belongs to is over and lets exec'd children
    # inherit it, so that they can open the path. Nothing ever waits for a
    # FIFO to be opened: `echo <(true)` leaves no child behind.
    def __proc_sub(command, direction)
      reader, writer = IO.pipe
      # Ruby makes its pipes non-blocking; an external command reading the
      # path would get EAGAIN ("Resource temporarily unavailable")
      Rubish.require_library('fcntl')
      [reader, writer].each { |io| io.fcntl(Fcntl::F_SETFL, io.fcntl(Fcntl::F_GETFL) & ~Fcntl::O_NONBLOCK) }
      child_end, shell_end = direction == :in ? [writer, reader] : [reader, writer]

      pid = fork do
        shell_end.close
        @proc_sub_fds = nil # the parent owns the pipe ends it keeps
        # Use the constants: $stdout/$stdin may be StringIOs under test
        if direction == :in
          STDOUT.reopen(child_end)
          $stdout = STDOUT
        else
          STDIN.reopen(child_end)
          $stdin = STDIN
        end
        child_end.close
        # The command keeps the shell's stderr, as in bash

        begin
          execute(command, skip_history_expansion: true)
          Kernel.exit(@last_status || 0)
        rescue => e
          $stderr.puts "rubish: #{e.message}"
          Kernel.exit(1)
        end
      end
      Process.detach(pid)
      child_end.close

      shell_end.close_on_exec = false
      (@proc_sub_fds ||= []) << shell_end
      "/dev/fd/#{shell_end.fileno}"
    end

    def __brace(pattern)
      # Expand brace patterns like {a,b,c} or {1..5}
      # Only expand if braceexpand option is enabled
      return [pattern] unless Builtins.set_option?('B')

      # Quotes inside an alternative (`{a,"b c"}`) are removed afterwards,
      # as bash expands braces before it removes quotes
      expand_braces(pattern).map do |word|
        word.match?(/["'\\]/) ? expand_multi_segment_word(word) : word
      end
    end

    # Filename expansion for a pattern with extglob operators. Lives here so
    # that both the REPL and the ExecutionContext (which run __glob) have it.
    def expand_extglob(pattern)
      # Convert extended glob pattern to regex and match files
      # First, get the directory to search in
      dir = File.dirname(pattern)
      dir = '.' if dir == pattern || dir.empty?

      # Build regex from the pattern
      regex = extglob_to_regex(File.basename(pattern))

      # Get all files in directory and filter by regex
      begin
        entries = if pattern.include?('/')
                    # For paths with directories, we need to handle differently
                    base_glob = pattern.gsub(/[?*+@!]\([^)]*\)/, '*')
                    Dir.glob(base_glob)
                  else
                    Dir.entries(dir).reject { |e| e.start_with?('.') }
                  end

        if pattern.include?('/')
          # Filter full paths
          full_regex = extglob_to_regex(pattern)
          entries.select { |f| f.match?(full_regex) }.sort
        else
          entries.select { |f| f.match?(regex) }.map { |f| dir == '.' ? f : File.join(dir, f) }.sort
        end
      rescue Errno::ENOENT
        []
      end
    end

    def __case_match(pattern, word)
      # Shell pattern matching using fnmatch
      # Supports *, ?, [...] patterns
      if pattern.include?('[:') || pattern.include?('[.') || pattern.include?('[=')
        icase = Builtins.shopt_enabled?('nocasematch')
        rx = posix_glob_to_regex(pattern, icase: icase)
        return rx ? rx.match?(word) : false
      end
      if Builtins.shopt_enabled?('extglob') && has_extglob?(pattern)
        rx = extglob_to_regex(pattern)
        rx = Regexp.new(rx.source, Regexp::IGNORECASE) if Builtins.shopt_enabled?('nocasematch')
        return rx.match?(word)
      end
      flags = File::FNM_EXTGLOB
      flags |= File::FNM_CASEFOLD if Builtins.shopt_enabled?('nocasematch')
      File.fnmatch(pattern, word, flags)
    end

    # Glob-escape a runtime value so its fnmatch metacharacters match
    # literally. Used for variables expanded inside a quoted case pattern,
    # where bash treats the expansion as literal text.
    def __glob_escape(str)
      str.to_s.gsub(/[\\*?\[\]]/) { |c| "\\#{c}" }
    end

    def __subshell(&block)
      # Create a Subshell object that can be run, redirected, or piped
      # Wrap the block to increment subshell level before executing (in the forked process)
      Subshell.new do
        Builtins.subshell_level += 1
        # The parent's traps are not inherited (ignored signals aside); an
        # EXIT trap set inside runs when the subshell ends, as in bash
        Builtins.reset_traps_for_subshell
        # `exit N` inside the subshell ends only the subshell: catch it here
        # and hand the status to Subshell#run. A plain `exit` uses $?.
        exited = true
        result = catch(:exit) do
          value = block.call
          exited = false
          value
        end
        status = exited ? ExitStatus.new(result || @last_status || 0) : result
        @last_status = status.exitstatus if status.respond_to?(:exitstatus) && status.exitstatus
        Builtins.exit_traps
        status
      end
    end

    def __negate(&block)
      # Run command and negate exit status; a function called here is
      # exempt from errexit inside, like one in a condition
      prev = @errexit_suppressed
      @errexit_suppressed = true
      begin
        status = __negated_command_status(&block)
      ensure
        @errexit_suppressed = prev
      end

      # A `!` command is exempt from errexit and the ERR trap, as in bash
      @errexit_exempt = true
      ExitStatus.new(status ? 1 : 0)
    end

    def __negated_command_status(&block)
      @last_subst_status = nil
      result = block.call

      # Handle different return types
      case result
      when ->(r) { __bare_assignment_command?(r) }
        # `! x=$(cmd)` negates the substitution's status
        status = __run_bare_assignment(result) == 0
      when ->(r) { r.is_a?(Command) && Command.function?(r.name) }
        # `! myfunc`: call the function here, not in a fork (bash)
        status = call_function_with_redirects(result).success?
      when Command, Pipeline, Subshell
        result.run unless result.ran?
        status = result.success?
        # `! a | b` still records each element's status
        if result.is_a?(Pipeline) && result.statuses
          @pipestatus = result.statuses.map { |s| ExitStatus.code_of(s) }
          @pipestatus_from_negation = true
        end
      when ExitStatus
        status = result.success?
      when true, false
        status = result
      when Integer
        status = result == 0
      else
        status = result ? true : false
      end
      status
    end

    def __heredoc(delimiter, expand, strip_tabs, compound = false, content = nil, &block)
      content ||= ''

      # Apply tab stripping if <<- was used
      if strip_tabs
        content = content.lines.map { |l| l.sub(/\A\t+/, '') }.join
      end

      # Apply variable expansion if not quoted
      if expand
        content = expand_heredoc_content(content)
      end

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, compound: compound, &block)
    end

    def __herestring(string, compound = false, &block)
      # Herestring provides a single string as stdin (with trailing newline)
      content = "#{string}\n"

      # Return a HeredocCommand that can be redirected and run later
      HeredocCommand.new(content, compound: compound, &block)
    end

    # Thread-safe lazy_load for eval "$(cmd)" pattern
    # Runs the command using Open3 (no fork from thread)
    def __lazy_load_eval(cmd)
      require_relative 'lazy_loader'

      LazyLoader.register(cmd, @state.executor) do
        # Run command using Open3 - thread-safe, no fork issues
        Rubish.require_library('open3')
        output, status = Open3.capture2(cmd)
        output.chomp
      end

      true
    end

    # Generic lazy_load for arbitrary blocks (may hang if block uses fork)
    def __lazy_load(&block)
      require_relative 'lazy_loader'

      # Derive name from caller location
      caller_loc = caller_locations(1, 1).first
      name = if caller_loc
               "#{File.basename(caller_loc.path)}:#{caller_loc.lineno}"
             else
               'lazy'
             end

      LazyLoader.register(name, @state.executor) do
        # Execute the block - it returns generated code result
        result = block.call

        # Handle the result based on type
        if result.is_a?(Command) && result.name == 'eval' && result.args.any?
          # For eval "$(cmd)" - the args contain the output to be eval'd
          # Return the first arg as shell code to execute in main thread
          result.args.first.to_s
        elsif result.is_a?(String)
          # Direct string result - execute as shell code
          result
        else
          # For other commands, run them and capture stdout
          if result.respond_to?(:run)
            old_stdout = $stdout
            captured = StringIO.new
            begin
              $stdout = captured
              result.run
            ensure
              $stdout = old_stdout
            end
            output = captured.string
            output.empty? ? nil : output
          else
            nil
          end
        end
      end

      true
    end

    def __coproc(name, &block)
      # Check if a coproc with this name already exists
      if Builtins.coproc?(name)
        $stderr.puts "rubish: coproc #{name}: already exists"
        return ExitStatus.new(1)
      end

      # Create bidirectional pipes
      # parent_read/child_write: child writes stdout, parent reads
      # child_read/parent_write: parent writes, child reads stdin
      parent_read, child_write = IO.pipe
      child_read, parent_write = IO.pipe

      pid = fork do
        # Child process
        parent_read.close
        parent_write.close

        # Redirect the real descriptors: the shell's $stdin/$stdout may be a
        # swapped Ruby object (compound redirect, embedder, test harness)
        STDIN.reopen(child_read)
        STDOUT.reopen(child_write)
        $stdin = STDIN
        $stdout = STDOUT
        child_read.close
        child_write.close

        # Reset signal handlers
        Kernel.trap('INT', 'DEFAULT')
        Kernel.trap('TSTP', 'DEFAULT')

        # Execute the command
        result = block.call
        result.run if result.is_a?(Command) || result.is_a?(Pipeline)
        Kernel.exit(result.respond_to?(:success?) && result.success? ? 0 : 1)
      end

      # Parent process
      child_read.close
      child_write.close

      # Store the coproc info
      Builtins.set_coproc(
        name,
        pid: pid,
        read_fd: parent_read.fileno,
        write_fd: parent_write.fileno,
        reader: parent_read,
        writer: parent_write
      )

      @last_bg_pid = pid
      # The notice is for interactive shells only, as in bash
      puts "[coproc] #{name} #{pid}" if Builtins.interactive_mode?

      ExitStatus.new(0)
    end

    def __time(posix_format = false, &block)
      # Measure execution time of a command
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      start_times = Process.times

      result = nil
      begin
        result = block.call
        if __bare_assignment_command?(result)
          # `time x=2`: the assignment is made here, in the shell
          result = ExitStatus.new(__run_bare_assignment(result))
        elsif result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell) || result.is_a?(HeredocCommand)
          result.run
        end
      rescue => e
        $stderr.puts "rubish: time: #{e.message}"
      end

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end_times = Process.times

      # Calculate times
      real = end_time - start_time
      user = (end_times.utime - start_times.utime) + (end_times.cutime - start_times.cutime)
      sys = (end_times.stime - start_times.stime) + (end_times.cstime - start_times.cstime)

      # Output timing information to stderr
      if posix_format
        # POSIX format: seconds with fractions
        $stderr.puts format('real %.2f', real)
        $stderr.puts format('user %.2f', user)
        $stderr.puts format('sys %.2f', sys)
      elsif !(timeformat = Builtins.get_var('TIMEFORMAT')).nil?
        # Custom TIMEFORMAT; an empty value prints nothing (bash)
        output = format_timeformat(timeformat, real, user, sys)
        $stderr.puts output unless output.empty?
      else
        # Default bash-like format
        $stderr.puts
        $stderr.puts format("real\t%dm%.3fs", (real / 60).to_i, real % 60)
        $stderr.puts format("user\t%dm%.3fs", (user / 60).to_i, user % 60)
        $stderr.puts format("sys\t%dm%.3fs", (sys / 60).to_i, sys % 60)
      end

      # Return the result's exit status
      if result.respond_to?(:status) && result.status
        # Command/Pipeline with status
        result.status.success? ? ExitStatus.new(0) : ExitStatus.new(result.status.exitstatus || 1)
      elsif result.respond_to?(:success?)
        result.success? ? ExitStatus.new(0) : ExitStatus.new(1)
      else
        ExitStatus.new(0)
      end
    end

    def __cond_test(parts)
      # Evaluate [[ ]] conditional expression
      # Returns ExitStatus based on expression result
      announce_texts(["[[ #{parts.map { |p| p.respond_to?(:source) ? p.source : p.to_s }.join(' ')} ]]"])
      result = eval_cond_expr(parts, 0, parts.length)
      ExitStatus.new(result ? 0 : 1)
    rescue RegexpError => e
      $stderr.puts "rubish: [[: invalid regular expression `#{e.message}'"
      ExitStatus.new(2)
    end

    def __cond_syntax_error(msg)
      $stderr.puts "rubish: [[: #{msg}"
      ExitStatus.new(2)
    end

    def __array_assign(var_part, elements)
      # Handle array assignment: VAR=(a b c) or VAR+=(d e)
      # var_part includes the = or +=, e.g., "arr=" or "arr+="

      append = var_part.end_with?('+=')
      var_name = var_part.chomp(append ? '+=' : '=')
      announce_texts(["#{var_part}(#{elements.map { |e| Tracing.trace_word(e.to_s) }.join(' ')})"])
      ok = Builtins.assign_array_literal(var_name, elements, append: append)

      ExitStatus.new(ok == false ? 1 : 0)
    end

    # `name=(elements)` given as an argument, e.g. `declare -a name=(1 2)`
    def __array_word(var_part, elements)
      ArrayWord.new(var_part, elements)
    end

    # $_ is the last argument of the previous command (its name when it has
    # none); for a pipeline, that of its last command
    def __remember_last_argument(result)
      cmd = result.is_a?(Pipeline) ? result.commands.last : result
      return unless cmd.is_a?(Command)

      Builtins.set_var('_', (cmd.args.last || cmd.name).to_s)
    end

    def __define_function(name, source_code = nil, params = nil, &block)
      if Builtins.current_state.readonly_functions.include?(name)
        $stderr.puts "rubish: #{name}: readonly function"
        @last_status = 1
        return nil
      end

      @functions[name] = {block: block, source: @current_source_file, source_code: source_code, lineno: @lineno, params: params}
      nil
    end

    # Builtins that must run in current process (affect shell state)
    PROCESS_BUILTINS = %w[cd export set shift source . return exit break continue local unset readonly declare typeset let eval command builtin shopt alias unalias trap
                          pushd popd dirs read mapfile readarray getopts umask ulimit hash wait jobs fg bg disown enable times history fc].freeze

    # Run a builtin in-process, applying its prefix env (e.g. `IFS= read`)
    # temporarily and restoring it after. Externals get this via fork+ENV;
    # in-process builtins need it set/restored around the call.
    def run_builtin_with_prefix(cmd)
      env = cmd.respond_to?(:prefix_env) ? cmd.prefix_env : nil
      Builtins.with_temporary_vars(env) { Builtins.run(cmd.name, cmd.args) }
    end

    # `exec` with redirections and no command rewires the shell's own fds.
    # Lives here (not only on REPL) so that `__run_cmd` can reach it when
    # exec is one command of a list: `exec 2>log; echo oops >&2`.
    def handle_exec_command(cmd)
      has_redirections = cmd.stdin || cmd.stdout || cmd.stderr
      has_fd_redirections = cmd.fd_redirects && !cmd.fd_redirects.empty?

      if cmd.args.empty?
        # exec with only redirections - modify the shell's descriptors permanently
        apply_exec_redirections(cmd) if has_redirections
        @last_status = has_fd_redirections ? apply_exec_fd_redirections(cmd) : 0
        run_err_trap_if_failed
      else
        # exec with a command: apply the redirections, then replace the
        # process. Descriptors opened here are inherited by the new program.
        apply_exec_redirections(cmd) if has_redirections
        apply_exec_fd_redirections(cmd) if has_fd_redirections
        success = Builtins.run('exec', cmd.args)
        @last_status = success ? 0 : 1
        run_err_trap_if_failed
      end
    end

    # Descriptors >= 3 opened with `exec N>file`, `exec N<file` or
    # `exec N>&M`, keyed by the shell-level number N. The IO's own fileno is
    # unrelated: Ruby reserves the low descriptors for itself, so N is only
    # a name. `>&N`, `<&N` and `read -u N` look it up here, and children get
    # it as their fd N through exec's redirect options.
    def shell_fds
      Builtins.current_state.shell_fds
    end

    # Returns the exit status: 1 if any descriptor could not be set up
    def apply_exec_fd_redirections(cmd)
      status = 0
      cmd.fd_redirects.each do |fd, spec|
        status = 1 unless apply_fd_redirect_spec(fd, spec)
      end
      status
    end

    # Make shell descriptor `fd` what `spec` says (see
    # Command.fd_redirect_spec), closing what it was before. false when the
    # source could not be opened or duplicated.
    def apply_fd_redirect_spec(fd, spec)
      io = case spec
           when :close
             nil
           when Integer
             source = Command.standard_or_shell_fd(spec)
             unless source
               $stderr.puts "rubish: #{spec}: Bad file descriptor"
               return false
             end
             source.dup
           when Array
             path, mode = spec
             begin
               File.open(path, mode)
             rescue SystemCallError => e
               $stderr.puts "rubish: #{path}: #{e.message.sub(/ @ .*/, '')}"
               return false
             end
           when IO
             spec
           end
      shell_fds.delete(fd)&.close
      shell_fds[fd] = io if io
      true
    end

    # Apply exec redirections to the current shell permanently
    def apply_exec_redirections(cmd)
      # Store original FDs if not already saved (for potential restore)
      @original_stdin ||= $stdin.dup
      @original_stdout ||= $stdout.dup
      @original_stderr ||= $stderr.dup

      # Apply redirections permanently to the shell's own streams
      @shell_stdin = exec_reopen($stdin, cmd.stdin) if cmd.stdin
      @shell_stdout = exec_reopen($stdout, cmd.stdout) if cmd.stdout
      @shell_stderr = exec_reopen($stderr, cmd.stderr) if cmd.stderr
    end

    # Point one of the shell's streams at a redirection target for good:
    # an opened file, or the `:stdout` / `:stderr` / `:closed` markers of
    # `exec 2>&1`, `exec >&2` and `exec >&-`. Returns the target's path.
    def exec_reopen(stream, target)
      case target
      when :stdout then stream.reopen($stdout)
      when :stderr then stream.reopen($stderr)
      when :closed then stream.reopen(File::NULL, 'w')
      else
        stream.reopen(target)
        target.close unless target.closed?
      end
      target.respond_to?(:path) ? target.path : target.to_s
    end

    # `VAR=value ...` with no command name: every word is an assignment
    def __bare_assignment_command?(result)
      result.is_a?(Command) && bare_assignment?(result.name) && result.args.all? { |a| bare_assignment?(a) }
    end

    # Perform the assignments and return the command's status: that of the
    # last command substitution expanded for it, or 0 (bash semantics). The
    # caller resets @last_subst_status before expanding the words.
    def __run_bare_assignment(result)
      ok = handle_bare_assignments([result.name] + result.args)
      @last_status = ok ? (@last_subst_status || 0) : 1
    end

    # Run a process-affecting builtin (cd, export, set, ...) in this process
    # while honouring the command's redirections: swap the global streams for
    # the duration so the builtin's output lands in the redirect target.
    # Forking, as external commands do, would lose the builtin's effect on
    # the shell (`cd dir > /dev/null` must still change directory).
    def __run_process_builtin(cmd)
      # A redirect that could not be set up (missing directory, noclobber,
      # restricted mode, bad fd) has already been reported: skip the builtin
      return ExitStatus.new(1) if cmd.restricted_failed || cmd.noclobber_failed

      saved_in, saved_out, saved_err = $stdin, $stdout, $stderr
      stdin, stdout, stderr = cmd.effective_streams
      $stdin = stdin if stdin.is_a?(IO)
      case stdout
      when IO then $stdout = stdout
      when :stderr then $stdout = saved_err
      end
      case stderr
      when IO then $stderr = stderr
      when :stdout then $stderr = saved_out
      end
      begin
        run_builtin_with_prefix(cmd)
      ensure
        [$stdout, $stderr].each { |io| io.flush if io.respond_to?(:flush) && !io.closed? }
        $stdin, $stdout, $stderr = saved_in, saved_out, saved_err
      end
    end

    def __run_cmd(&block)
      result = __closing_proc_subs { __run_cmd_body(&block) }
      result.reported = true if result.is_a?(ExitStatus)
      result
    end

    def __run_cmd_body(&block)
      @last_subst_status = nil
      begin
        result = block.call
      rescue ArithmeticEvaluator::Error => e
        # Bad arithmetic in this command's words aborts just this command
        # (status 1) and the list goes on, as in bash
        $stderr.puts "rubish: #{e.message}"
        @last_status = 1
        @pipestatus = [1]
        run_err_trap_if_failed
        check_errexit
        return ExitStatus.new(1)
      end

      announce_command(result)

      # Run DEBUG trap before each command
      Builtins.debug_trap

      __remember_last_argument(result)

      if result.is_a?(Command) && result.name == 'exec'
        # Special handling for exec builtin
        handle_exec_command(result)
        result
      elsif result.is_a?(Command) && PROCESS_BUILTINS.include?(result.name) && !@functions.key?(result.name)
        # Run process-affecting builtins directly in current process
        success = __run_process_builtin(result)
        @last_status = success.is_a?(ExitStatus) ? success.exitstatus : (success ? 0 : 1)
        @pipestatus = [@last_status]
        run_err_trap_if_failed
        check_errexit
        # Return ExitStatus to prevent eval_in_context from trying to run command again
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && Builtins.builtin?(result.name) && !result.stdout && !result.stderr && !@functions.key?(result.name)
        # Run builtins without explicit redirects in current process
        # This allows them to respect $stdout set by __with_redirect for compound commands.
        # If a redirect was attempted but its target file couldn't be opened,
        # the error has already been printed by redirect_*; skip execution so
        # the builtin doesn't run with the original (unredirected) streams.
        if result.restricted_failed || result.noclobber_failed
          @last_status = 1
          @pipestatus = [@last_status]
          run_err_trap_if_failed
          check_errexit
          return ExitStatus.new(@last_status)
        end
        success = __run_process_builtin(result)
        @last_status = success.is_a?(ExitStatus) ? success.exitstatus : (success ? 0 : 1)
        @pipestatus = [@last_status]
        run_err_trap_if_failed
        check_errexit
        # Return ExitStatus so callers (like Subshell) know the real exit status
        ExitStatus.new(@last_status)
      elsif result.is_a?(Command) && @functions.key?(result.name)
        # Call user-defined function with redirects
        status = call_function_with_redirects(result)
        @pipestatus = [@last_status]
        # A failing call runs the ERR trap here, at the call site; inside the
        # function it ran only with errtrace
        run_err_trap_if_failed
        check_errexit
        # Return ExitStatus (not the Command) to prevent eval_in_context from calling the function again
        status
      elsif result.is_a?(Command) && bare_assignment?(result.name) && result.args.all? { |a| bare_assignment?(a) }
        # Handle bare variable assignments in lists (VAR=value). Return an
        # ExitStatus so the caller sees this status rather than the unrun Command's.
        # `x=$(false)` fails like any command: ERR trap and errexit apply
        status = __run_bare_assignment(result)
        run_err_trap_if_failed
        check_errexit
        ExitStatus.new(status)
      else
        # A command an inner __run_cmd already ran (a list in a group) had
        # its ERR trap and errexit handled there
        handled = result.respond_to?(:ran?) && result.ran?
        result.run if result.is_a?(Command) || result.is_a?(Pipeline) || result.is_a?(Subshell) || result.is_a?(HeredocCommand)
        if result.respond_to?(:status)
          @last_status = ExitStatus.code_of(result.status)
          # Update PIPESTATUS array
          if result.is_a?(Pipeline) && result.statuses
            @pipestatus = result.statuses.map { |s| ExitStatus.code_of(s) }
          else
            @pipestatus = [@last_status]
          end
          unless handled
            run_err_trap_if_failed
            check_errexit
          end
        elsif result.respond_to?(:exitstatus)
          # Handle ExitStatus objects (from __cond_test, etc.)
          @last_status = result.exitstatus || 0
          # `! a | b` keeps the pipeline's statuses (bash)
          @pipestatus = [@last_status] unless @pipestatus_from_negation
          @pipestatus_from_negation = false
          unless result.respond_to?(:reported) && result.reported
            run_err_trap_if_failed
            check_errexit
          end
        end
        result
      end
    end
  end
end
