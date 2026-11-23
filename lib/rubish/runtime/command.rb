# frozen_string_literal: true

module Rubish
  # Terminal control functions for job control
  module Terminal
    STDIN_FD = 0

    # tcsetpgrp/tcgetpgrp via Fiddle, loaded on first use: only interactive
    # job control needs them, and loading fiddle costs ~8 ms at startup
    def self.libc
      @libc ||= begin
        Rubish.require_library('fiddle')
        Rubish.require_library('fiddle/import')
        importer = Module.new
        importer.extend Fiddle::Importer
        importer.dlload Fiddle::Handle::DEFAULT
        importer.extern 'int tcsetpgrp(int, int)'
        importer.extern 'int tcgetpgrp(int)'
        importer
      end
    end

    # Give terminal control to a process group
    def self.set_foreground(pgid)
      libc.tcsetpgrp(STDIN_FD, pgid)
    rescue StandardError, LoadError
      # Not a tty, no terminal control, or fiddle not installed
    end

    # Get current foreground process group
    def self.get_foreground
      libc.tcgetpgrp(STDIN_FD)
    rescue StandardError, LoadError
      nil
    end

    # Check if stdin is a tty
    def self.tty?
      $stdin.tty?
    rescue IOError
      false
    end
  end

  # Simple exit status for builtins
  ExitStatus = Struct.new(:exitstatus) do
    def success?
      exitstatus == 0
    end

    # The shell's view of a Process::Status (or anything with #exitstatus):
    # the exit code, or 128+signal when the process was killed, as bash
    # reports it in $? and PIPESTATUS. nil means "no status": 0.
    def self.code_of(status)
      return 0 if status.nil?

      code = status.exitstatus
      return code if code
      return 128 + status.termsig if status.respond_to?(:termsig) && status.termsig

      0
    end
  end

  # Status for noclobber failures
  class NoclobberStatus
    def exitstatus
      1
    end

    def success?
      false
    end
  end

  # Status for restricted mode failures
  class RestrictedStatus
    def exitstatus
      1
    end

    def success?
      false
    end
  end

  class Command
    attr_reader :name, :pid, :status, :restricted_failed, :noclobber_failed, :fd_redirects
    attr_accessor :stdin, :stdout, :stderr, :block, :prefix_env
    # The pipe a Pipeline gave this element as its stdout (see effective_streams)
    attr_accessor :pipe_stdout

    # Class-level accessors for function support in pipelines
    @function_checker = nil
    @function_caller = nil

    class << self
      attr_accessor :function_checker, :function_caller
    end

    def self.function?(name)
      @function_checker&.call(name) || false
    end

    def self.call_function(name, args)
      @function_caller&.call(name, args)
    end

    # Hook the host can install to run extra setup in the child between
    # fork() and exec(). Used by in-process embeddings (e.g. Echoes) to
    # set up a per-command pty controlling-tty (setsid + TIOCSCTTY) so
    # signals from the line discipline (Ctrl-C → SIGINT) reach the
    # child. nil = no-op.
    class << self
      attr_accessor :child_pre_exec_hook
    end

    # Apply stdin/stdout/stderr redirections in a forked child. Each target
    # is an IO, nil (inherit), or a symbol: :closed, :stderr (for stdout,
    # `>&2`), or :stdout (for stderr, `2>&1` / `|&`).
    def self.apply_child_redirections(stdin, stdout, stderr)
      # The child needs the real descriptors. A compound redirect
      # (`{ ...; } > file`, `while ...; done < file`) only swapped the shell's
      # Ruby streams, so point fds 0-2 at those streams first: the program
      # exec'd below inherits descriptors, not Ruby objects. An embedder (or
      # a test) may have swapped in a non-IO such as StringIO; those are
      # ignored and the real streams used.
      [[STDIN, $stdin], [STDOUT, $stdout], [STDERR, $stderr]].each do |real, current|
        next unless current.is_a?(IO) && !current.equal?(real) && !current.closed?

        real.reopen(current)
      end
      $stdin = STDIN
      $stdout = STDOUT
      $stderr = STDERR

      if stdin == :closed
        $stdin.close
      elsif stdin
        $stdin.reopen(stdin)
      end

      # `>&2` / `2>&1` that refer to the original streams (see
      # Command#effective_streams) are applied before those streams are
      # pointed elsewhere
      $stdout.reopen($stderr) if stdout == :stderr
      $stderr.reopen($stdout) if stderr == :stdout

      if stdout == :closed
        $stdout.close
      elsif stdout && !stdout.is_a?(Symbol)
        $stdout.reopen(stdout)
      end

      if stderr == :closed
        $stderr.close
      elsif stderr && !stderr.is_a?(Symbol)
        $stderr.reopen(stderr)
      end
    end

    # A descriptor the shell opened with `exec N>file`, or nil
    def self.shell_fd(n)
      Builtins.current_state&.shell_fds&.[](n)
    end

    # The IO behind a numeric redirect target: the standard streams for
    # 0, 1 and 2, otherwise a descriptor opened with `exec N>file`
    def self.standard_or_shell_fd(n)
      case n
      when 0 then $stdin
      when 1 then $stdout
      when 2 then $stderr
      else shell_fd(n)
      end
    end

    # Redirect options for Kernel#exec in a child: the shell's persistent
    # descriptors under their own numbers, overlaid with this command's
    # `N>` redirects. `N>&M` naming a persistent descriptor resolves to its
    # IO, since exec's `fd => M` would mean the parent's real fd M.
    def self.child_fd_options(fd_redirects)
      options = {}
      Builtins.current_state&.shell_fds&.each { |n, io| options[n] = io unless io.closed? }
      fd_redirects&.each do |fd, spec|
        persistent = spec.is_a?(Integer) && spec >= 3 ? shell_fd(spec) : nil
        options[fd] = persistent || spec
      end
      options.empty? ? nil : options
    end

    def next_redirect_seq
      @redirect_seq = (@redirect_seq || 0) + 1
    end

    # The streams to give the command, with `>&2` and `2>&1` resolved in the
    # order the redirections were written: `2>file >&2` sends stdout to the
    # file, while `2>&1 >file` sends stderr to the original stdout.
    def effective_streams
      out, err = @stdout, @stderr
      if out == :stderr && err == :stdout
        # Each dup takes the other stream as it was at that point: after
        # `2>&1 1>&2` both go where stdout went (the pipe, or stdout itself);
        # after `1>&2 2>&1` both go to stderr
        if (@stderr_seq || 0) < (@stdout_seq || 0)
          out = @pipe_stdout
          err = @pipe_stdout || :stdout
        else
          err = nil
        end
      end
      out = err if out == :stderr && err.is_a?(IO) && (@stderr_seq || 0) < (@stdout_seq || 0)
      err = @stdout if err == :stdout && @stdout.is_a?(IO) && (@stdout_seq || 0) < (@stderr_seq || 0)
      # In a pipeline the pipe was stdout before any redirection, so
      # `2>&1 >file` sends stderr down the pipe
      err = @pipe_stdout if err == :stdout && @pipe_stdout
      [@stdin, out, err]
    end

    # Execute a command with proper error handling for command not found / permission denied
    # Run a builtin or function inside a forked child and return the code
    # the child should exit with. `exit` (and errexit) throw :exit, which
    # nothing else in the child would catch
    def self.child_status(name = nil)
      code = catch(:exit) do
        result = yield
        return result.is_a?(ExitStatus) ? result.exitstatus : (result ? 0 : 1)
      end
      code.to_i
    rescue IOError, Errno::EBADF, Errno::EPIPE
      # `echo x >&-`: the builtin wrote to a closed descriptor (bash: status 1)
      $stderr.puts "rubish: #{name}: write error: Bad file descriptor" unless $stderr.closed?
      1
    end

    def self.safe_exec(cmd_name, cmd_path, *args, fd_options: nil)
      child_pre_exec_hook&.call
      if fd_options && !fd_options.empty?
        exec(cmd_path, *args, fd_options)
      else
        exec(cmd_path, *args)
      end
    rescue Errno::ENOENT
      $stderr.puts "rubish: #{cmd_name}: command not found"
      suggestions = suggest_similar_commands(cmd_name)
      unless suggestions.empty?
        $stderr.puts "Did you mean?  #{suggestions.join("\n               ")}"
      end
      exit(127)
    rescue Errno::EACCES
      $stderr.puts "rubish: #{cmd_path}: Permission denied"
      exit(126)
    end

    # Get all available commands from PATH directories
    def self.available_commands
      @available_commands_cache ||= begin
        commands = Set.new
        path_dirs = (ENV['PATH'] || '').split(File::PATH_SEPARATOR)
        path_dirs.each do |dir|
          next unless File.directory?(dir)
          begin
            Dir.foreach(dir) do |entry|
              next if entry.start_with?('.')
              full_path = File.join(dir, entry)
              commands << entry if File.executable?(full_path) && !File.directory?(full_path)
            end
          rescue Errno::ENOENT, Errno::EACCES
            # Skip directories we can't read
          end
        end
        commands.to_a
      end
    end

    # Suggest similar command names using did_you_mean
    def self.suggest_similar_commands(cmd_name)
      spell_checker = DidYouMean::SpellChecker.new(dictionary: available_commands)
      spell_checker.correct(cmd_name)
    end

    # Clear the available commands cache (useful when PATH changes)
    def self.clear_command_cache
      @available_commands_cache = nil
    end

    def initialize(name, *args, skip_functions: false, &block)
      @name = name
      @args = expand_args(args)
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @block = block
      @ran = false
      @skip_functions = skip_functions
      # Lazy-set elsewhere; pre-init so Ruby 2.6's stricter -W doesn't
      # emit "instance variable @xxx not initialized" warnings when
      # they're first read. Those warnings hit stderr and bleed into
      # capture_stderr-based tests (test_restricted, test_time).
      @noclobber_failed = false
      @restricted_failed = false
      @prefix_env = nil
      @status = nil
      # Redirects for fds >= 3, keyed by source fd. Values are Kernel#exec
      # redirect specs: `:close`, an Integer (dup), or `[file, mode]`.
      @fd_redirects = nil
    end

    def args
      @args
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      # If noclobber prevented redirection, fail without running
      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      # If restricted mode prevented redirection, fail without running
      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      if @block
        run_with_block
      else
        run_simple
      end
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      # Check noclobber: if set and file exists, fail
      if Builtins.set_option?('C') && File.file?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_clobber(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      # Force overwrite even with noclobber (>|)
      @stdout = File.open(file, 'w')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_append(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err(file)
      # Restricted mode: cannot redirect output
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      @stderr_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_append(file)
      # 2>>file - append stderr to file
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'a')
      @stderr_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_to_out
      # Used for |& - redirect stderr to stdout before piping
      @stderr = :stdout
      self
    end

    def dup_out(target)
      # >&N - duplicate stdout to file descriptor N
      # >&- - close stdout
      # >&file - redirect stdout to file (same as >file)
      case target
      when '1'
        # >&1 - no-op, stdout already goes to stdout
        self
      when '2'
        # >&2 - redirect stdout to stderr
        @stdout = :stderr
        @stdout_seq = next_redirect_seq
        self
      when '-'
        # >&- - close stdout
        @stdout = :closed
        self
      else
        # >&N: a descriptor opened with `exec N>file`; any other number is
        # an error, not a file named "N"
        if target.match?(/\A\d+\z/)
          io = own_or_shell_fd(target.to_i)
          return bad_file_descriptor(target) unless io

          @stdout = io.dup
          return self
        end

        # >&file - redirect to file
        redirect_out(target)
      end
    end

    # bash: `3: Bad file descriptor`; the command is skipped with status 1
    def bad_file_descriptor(fd)
      $stderr.puts "rubish: #{fd}: Bad file descriptor"
      @restricted_failed = true
      self
    end

    def dup_in(target)
      # <&N - duplicate stdin from file descriptor N
      # <&- - close stdin
      case target
      when '0'
        # <&0 - no-op
        self
      when '-'
        # <&- - close stdin
        @stdin = :closed
        self
      else
        if target.match?(/\A\d+\z/)
          io = own_or_shell_fd(target.to_i)
          return bad_file_descriptor(target) unless io

          @stdin = io.dup
          return self
        end

        # <&file - treat as input redirect
        redirect_in(target)
      end
    end

    def dup_err(target)
      # 2>&N - duplicate stderr to file descriptor N
      # 2>&- - close stderr
      # 2>&file - redirect stderr to file (same as 2>file)
      case target
      when '1'
        @stderr = :stdout
        @stderr_seq = next_redirect_seq
        self
      when '2'
        self
      when '-'
        @stderr = :closed
        self
      else
        if target.match?(/\A\d+\z/)
          io = own_or_shell_fd(target.to_i)
          return bad_file_descriptor(target) unless io

          @stderr = io.dup
          return self
        end

        redirect_err(target)
      end
    end

    # `N>file`, `N>>file`, `N>|file`, `N<file`, `N>&M`, `N<&M`, `N>&-`,
    # `N<&-` for fds N >= 3. Records the redirect against the source fd;
    # run_simple applies them via Kernel#exec's redirect-options hash.
    def fd_redirect(fd, op, target)
      @fd_redirects ||= {}
      spec = Command.fd_redirect_spec(op, target)
      @fd_redirects[fd] = spec unless spec.nil?
      self
    end

    # The IO behind `>&N` / `<&N` for this command: its own `N<file` or
    # `N<<< word` redirection when it has one (`cat 3<<< hi <&3`), else the
    # shell's descriptor N. A path spec is opened once and kept, so the
    # child's fd N and the duplicated stream share the same open file.
    def own_or_shell_fd(n)
      spec = @fd_redirects && @fd_redirects[n]
      case spec
      when IO then spec
      when Array
        @fd_redirects[n] = File.open(*spec)
      when Integer then Command.standard_or_shell_fd(spec)
      else Command.shell_fd(n)
      end
    rescue SystemCallError
      nil
    end
    
    # What descriptor N gets for `N<op> target`: [path, mode] to open, an
    # Integer descriptor to duplicate, :close, or an IO holding a
    # herestring (`N<<< word`). nil for an operator this cannot express.
    def self.fd_redirect_spec(op, target)
      case op
      when '>', '>|' then [target, 'w']
      when '>>' then [target, 'a']
      when '<' then [target, 'r']
      when '<<<' then content_file("#{target}\n")
      when '>&', '<&'
        if target == '-'
          :close
        elsif target =~ /\A\d+\z/
          target.to_i
        else
          # `N>&file` is just `N>file`.
          [target, op == '>&' ? 'w' : 'r']
        end
      end
    end

    # A seekable, unlinked file holding heredoc or herestring content. A
    # regular file rather than a pipe: a body larger than the pipe buffer
    # cannot deadlock, and `read` can hand unread bytes back to the next
    # reader (see Builtins#read_input_line).
    def self.content_file(content)
      Rubish.require_library('tempfile')
      file = Tempfile.create('rubish-heredoc')
      file.write(content)
      file.flush
      file.rewind
      File.unlink(file.path)
      file
    end

    private

    def expand_args(args)
      # Globs are expanded at codegen level, here we just handle types
      args.flat_map do |arg|
        case arg
        when ArrayWord
          arg
        when Array
          arg.map(&:to_s)
        when Regexp
          arg.source
        else
          arg.to_s
        end
      end
    end

    def run_simple
      # Restricted mode: cannot run commands containing '/'
      if Builtins.restricted_mode? && name.include?('/')
        $stderr.puts "rubish: #{name}: restricted: cannot specify `/' in command names"
        @status = RestrictedStatus.new
        return self
      end

      # Resolve command path before forking (so hash updates are visible in parent)
      cmd_path = resolve_command_path(name)

      # Diagnose an unknown command here instead of after fork+exec: no need
      # to fork the whole interpreter just to fail, and the PATH scan behind
      # "Did you mean?" stays memoized in the shell process instead of being
      # redone in every short-lived child.
      if command_not_found?(cmd_path)
        report_command_not_found
        @status = ExitStatus.new(127)
        return self
      end

      # Extract keyword assignments if -k is set
      cmd_args, keyword_env = extract_keyword_assignments(@args)

      # Check if job control (monitor mode) is enabled
      job_control = Builtins.set_option?('m')

      @pid = fork do
        # Set up job control in child if enabled
        if job_control
          # Create new process group with this process as leader
          Process.setpgid(0, 0)
          # Reset signal handlers so Ctrl-Z works
          Kernel.trap('TSTP', 'DEFAULT')
          Kernel.trap('TTIN', 'DEFAULT')
          Kernel.trap('TTOU', 'DEFAULT')
        end

        Command.apply_child_redirections(*effective_streams)

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        # Set prefix environment variables (e.g., FOO=bar cmd)
        @prefix_env&.each { |k, v| ENV[k] = v }

        # Check if this is a user-defined function (unless skip_functions is set)
        if !@skip_functions && Command.function?(name)
          exit(Command.child_status(name) { Command.call_function(name, cmd_args) })
        elsif Builtins.builtin?(name)
          # A builtin that reached the fork because of its redirections:
          # run it here, on the redirected streams, rather than exec'ing a
          # same-named external (or failing when there is none, as for
          # `help cd > file` or `history > file`)
          exit(Command.child_status(name) { Builtins.run(name, cmd_args) })
        elsif cmd_path.include?('/') && File.directory?(cmd_path)
          # Only check for directory if path was explicitly given or resolved
          # Don't check bare command names against current directory
          $stderr.puts "rubish: #{cmd_path}: Is a directory"
          exit(126)
        else
          Command.safe_exec(name, cmd_path, *cmd_args, fd_options: Command.child_fd_options(@fd_redirects))
        end
      end

      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)
      @stdout&.close unless @stdout == $stdout || @stdout.is_a?(Symbol)

      if job_control
        # Set process group in parent too (race condition protection)
        Process.setpgid(@pid, @pid) rescue nil

        shell_pgid = Process.getpgrp

        # Use 'IGNORE' for SIGTTOU/SIGTTIN (maps to SIG_IGN) so tcsetpgrp works from background
        # Use a noop proc for SIGCHLD because 'IGNORE' causes OS to auto-reap children
        noop = proc {}
        old_chld = Kernel.trap('CHLD', noop)
        old_ttou = Kernel.trap('TTOU', 'IGNORE')
        old_ttin = Kernel.trap('TTIN', 'IGNORE')

        # Give terminal control to the child process group
        # This allows the child to receive Ctrl-Z (SIGTSTP)
        Terminal.set_foreground(@pid) if Terminal.tty?

        begin
          # Wait with WUNTRACED to detect stopped processes (Ctrl-Z)
          _, @status = Process.wait2(@pid, Process::WUNTRACED)
        ensure
          # Take back terminal control BEFORE restoring signal handlers
          Terminal.set_foreground(shell_pgid) if Terminal.tty?

          # Restore signal handlers after we have terminal control back
          Kernel.trap('CHLD', old_chld || 'DEFAULT')
          Kernel.trap('TTOU', old_ttou || 'DEFAULT')
          Kernel.trap('TTIN', old_ttin || 'DEFAULT')
        end

        # If the process was stopped, add it to the job manager
        if @status&.stopped?
          command_str = ([name] + @args).join(' ')
          job = JobManager.instance.add(
            pid: @pid,
            pgid: @pid,
            command: command_str
          )
          job.status = :stopped
          $stderr.puts "\n[#{job.id}]+  Stopped                 #{command_str}"
        end
      else
        Process.wait(@pid)
        @status = $?
      end
      self
    end

    def run_with_block
      reader, writer = IO.pipe

      # Resolve command path before forking (so hash updates are visible in parent)
      cmd_path = resolve_command_path(name)

      # Extract keyword assignments if -k is set
      cmd_args, keyword_env = extract_keyword_assignments(@args)

      @pid = fork do
        reader.close
        $stdin.reopen(@stdin) if @stdin
        $stdout.reopen(writer)
        if @stderr == :stdout
          # |& - redirect stderr to stdout (which is now writer)
          $stderr.reopen($stdout)
        elsif @stderr
          $stderr.reopen(@stderr)
        end

        # Set keyword environment variables
        keyword_env.each { |k, v| ENV[k] = v }

        # Set prefix environment variables (e.g., FOO=bar cmd)
        @prefix_env&.each { |k, v| ENV[k] = v }

        Command.safe_exec(name, cmd_path, *cmd_args, fd_options: Command.child_fd_options(@fd_redirects))
      end

      writer.close
      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)

      # Yield each line to block
      reader.each_line do |line|
        @block.call(line.chomp)
      end
      reader.close

      Process.wait(@pid)
      @status = $?
      self
    end

    # A path that does not exist, or a bare name that is neither a function,
    # a builtin, nor anywhere on PATH. (Permission and is-a-directory errors
    # on an existing path are still reported by the child after exec.)
    def command_not_found?(cmd_path)
      return !File.exist?(cmd_path) if name.include?('/')
      return false if cmd_path != name
      return false if !@skip_functions && Command.function?(name)
      return false if Builtins.builtin?(name)

      Builtins.find_in_path(name).nil?
    end

    def report_command_not_found
      err = case @stderr
            when :closed then return
            when :stdout then $stdout
            when IO then @stderr
            else $stderr
            end
      if name.include?('/')
        err.puts "rubish: #{name}: No such file or directory"
      else
        err.puts "rubish: #{name}: command not found"
        suggestions = Command.suggest_similar_commands(name)
        err.puts "Did you mean?  #{suggestions.join("\n               ")}" unless suggestions.empty?
      end
      # The target may be a redirect file the caller reads right away
      err.flush if err.respond_to?(:flush)
    end

    def resolve_command_path(cmd)
      # If absolute path or not using hashall, return as-is
      return cmd if cmd.include?('/') || !Builtins.set_option?('h')

      # `PATH=dirs cmd`: the assignment governs this lookup, and the hash
      # table, built from the shell's own PATH, does not apply
      if (prefix_path = @prefix_env&.[]('PATH'))
        return find_executable_in(prefix_path, cmd) || cmd
      end

      # Check hash first
      cached = Builtins.hash_lookup(cmd)
      if cached && !Builtins.execignore?(cached)
        # checkhash: verify the cached path is still valid
        if Builtins.shopt_enabled?('checkhash')
          unless File.executable?(cached) && !File.directory?(cached)
            # Cached path is no longer valid, remove from hash and re-search
            Builtins.hash_delete(cmd)
            cached = nil
          end
        end
        return cached if cached
      end

      # Search PATH and cache if found
      if (full_path = find_executable_in(ENV['PATH'], cmd))
        Builtins.hash_store(cmd, full_path)
        return full_path
      end

      # Not found in PATH, return original (exec will fail with proper error)
      cmd
    end

    def find_executable_in(path, cmd)
      (path || '').split(File::PATH_SEPARATOR).each do |dir|
        full_path = File.join(dir, cmd)
        next if Builtins.execignore?(full_path)
        return full_path if File.executable?(full_path) && !File.directory?(full_path)
      end
      nil
    end

    def extract_keyword_assignments(args)
      # When -k (keyword) is set, extract VAR=value from all args
      return [args, {}] unless Builtins.set_option?('k')

      keyword_env = {}
      remaining_args = []

      args.each do |arg|
        if arg.is_a?(String) && arg.match?(/\A[A-Za-z_][A-Za-z0-9_]*=/)
          # This is a keyword assignment
          name, value = arg.split('=', 2)
          keyword_env[name] = value || ''
        else
          remaining_args << arg
        end
      end

      [remaining_args, keyword_env]
    end
  end

  class Pipeline
    attr_reader :commands, :status, :statuses
    attr_accessor :block

    def initialize(*commands)
      @commands = commands.flatten
      @ran = false
      @block = nil
    end

    def |(other)
      @commands << other
      self
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run(&block)
      return self if @ran
      @ran = true

      if block || @block
        run_with_block(block || @block)
      else
        run_simple
      end
    end

    def redirect_out(file)
      @commands.last.redirect_out(file)
      self
    end

    def redirect_clobber(file)
      @commands.last.redirect_clobber(file)
      self
    end

    def redirect_append(file)
      @commands.last.redirect_append(file)
      self
    end

    def redirect_in(file)
      @commands.first.redirect_in(file)
      self
    end

    def redirect_err(file)
      @commands.last.redirect_err(file)
      self
    end

    def redirect_err_append(file)
      @commands.last.redirect_err_append(file)
      self
    end

    def redirect_err_to_out
      @commands.last.redirect_err_to_out
      self
    end

    def dup_out(target)
      @commands.last.dup_out(target)
      self
    end

    def dup_in(target)
      @commands.last.dup_in(target)
      self
    end

    def dup_err(target)
      @commands.last.dup_err(target)
      self
    end

    def fd_redirect(fd, op, target)
      @commands.last.fd_redirect(fd, op, target)
      self
    end

    private

    def run_simple
      # Check if lastpipe is enabled - run last command in current shell
      use_lastpipe = Builtins.shopt_enabled?('lastpipe') && @commands.length > 1

      # Check if job control (monitor mode) is enabled
      job_control = Builtins.set_option?('m')

      # Set up pipes between commands
      pipes = (@commands.length - 1).times.map { IO.pipe }

      # Determine which commands to fork (all except last if lastpipe)
      fork_count = use_lastpipe ? @commands.length - 1 : @commands.length

      # For job control, all processes in the pipeline share a process group
      # The first process's PID becomes the PGID
      pgid = nil

      pids = @commands[0...fork_count].each_with_index.map do |cmd, i|
        # Set stdin from previous pipe (except first command)
        cmd.stdin ||= pipes[i - 1][0] if i > 0

        # Set stdout to next pipe (except last command, but we're not forking last with lastpipe)
        cmd.stdout ||= pipes[i][1] if i < @commands.length - 1
        cmd.pipe_stdout = pipes[i][1] if i < @commands.length - 1

        fork do
          begin
          # Set up job control in child if enabled
          if job_control
            # First process becomes the process group leader
            # Others join that process group
            if pgid
              Process.setpgid(0, pgid)
            else
              Process.setpgid(0, 0)
            end
            # Reset signal handlers so Ctrl-Z works
            Kernel.trap('TSTP', 'DEFAULT')
            Kernel.trap('TTIN', 'DEFAULT')
            Kernel.trap('TTOU', 'DEFAULT')
          end

          # Close unused pipe ends
          pipes.each_with_index do |(reader, writer), j|
            if j == i - 1
              writer.close  # close write end of our input pipe
            elsif j == i
              reader.close  # close read end of our output pipe
            else
              reader.close
              writer.close
            end
          end

          Command.apply_child_redirections(*cmd.effective_streams)

          # Set prefix environment variables (e.g., FOO=bar cmd)
          cmd.prefix_env&.each { |k, v| ENV[k] = v } if cmd.respond_to?(:prefix_env)

          # Handle different command types
          if cmd.is_a?(Subshell)
            # Run subshell block
            result = cmd.instance_variable_get(:@block).call
            result.run if result.is_a?(Command) || result.is_a?(Pipeline)
            exit(Subshell.exit_code_for(result))
          elsif cmd.is_a?(HeredocCommand)
            # Run heredoc command in child process
            cmd.run
            exit(cmd.success? ? 0 : 1)
          elsif Command.function?(cmd.name)
            exit(Command.child_status(cmd.name) { Command.call_function(cmd.name, cmd.args) })
          elsif Builtins.builtin?(cmd.name)
            # Run builtin in forked process (e.g., history | grep)
            exit(Command.child_status(cmd.name) { Builtins.run(cmd.name, cmd.args) })
          else
            Command.safe_exec(cmd.name, cmd.name, *cmd.args, fd_options: Command.child_fd_options(cmd.fd_redirects))
          end
          rescue ParameterExpansionError, NounsetError, ArithmeticEvaluator::Error, ShellSyntaxError => e
            # An expansion error inside the child ends only this element, as
            # it would end the command in the shell; 127 is what bash gives
            $stderr.puts "rubish: #{e.message}"
            exit(127)
          end
        end.tap do |pid|
          # Set up process group in parent (first process becomes leader)
          if job_control
            if pgid.nil?
              pgid = pid
              Process.setpgid(pid, pid) rescue nil
            else
              Process.setpgid(pid, pgid) rescue nil
            end
          end
        end
      end

      # Handle lastpipe: run last command in current shell
      last_status = nil
      if use_lastpipe
        last_cmd = @commands.last
        last_pipe_reader = pipes.last[0]

        # Close write ends of all pipes in parent
        pipes.each { |_, writer| writer.close }

        # Close read ends of pipes except the last one (which we'll use for stdin)
        pipes[0...-1].each { |reader, _| reader.close }

        # Save original stdin
        original_stdin = $stdin.dup

        begin
          # Redirect stdin to read from the pipe
          $stdin.reopen(last_pipe_reader)

          # Run the last command in current shell
          if last_cmd.is_a?(Subshell) || last_cmd.is_a?(HeredocCommand)
            # A brace group or loop as the last element runs here too, so a
            # variable it sets stays set (bash)
            result = if last_cmd.is_a?(Subshell)
                       last_cmd.instance_variable_get(:@block).call
                     else
                       last_cmd.run
                       last_cmd
                     end
            result.run if result.is_a?(Command) || result.is_a?(Pipeline)
            last_status = ExitStatus.new(Subshell.exit_code_for(result))
          elsif last_cmd.is_a?(Command) && Builtins.builtin?(last_cmd.name)
            success = Builtins.run(last_cmd.name, last_cmd.args)
            last_status = ExitStatus.new(success ? 0 : 1)
          elsif last_cmd.is_a?(Command) && Command.function?(last_cmd.name)
            result = Command.call_function(last_cmd.name, last_cmd.args)
            last_status = ExitStatus.new(result ? 0 : 1)
          else
            # External command - must fork
            pid = fork do
              $stdout.reopen(last_cmd.stdout) if last_cmd.stdout
              $stderr.reopen(last_cmd.stderr) if last_cmd.stderr
              Command.safe_exec(last_cmd.name, last_cmd.name, *last_cmd.args, fd_options: Command.child_fd_options(last_cmd.fd_redirects))
            end
            Process.wait(pid)
            last_status = $?
          end
        ensure
          # Restore original stdin
          $stdin.reopen(original_stdin)
          original_stdin.close
          last_pipe_reader.close
        end
      else
        # Parent closes all pipe ends
        pipes.each do |reader, writer|
          reader.close
          writer.close
        end
      end

      shell_pgid = Process.getpgrp
      stopped = false

      if job_control && pgid
        # Use 'IGNORE' for SIGTTOU/SIGTTIN (maps to SIG_IGN) so tcsetpgrp works from background
        # Use a noop proc for SIGCHLD because 'IGNORE' causes OS to auto-reap children
        noop = proc {}
        old_chld = Kernel.trap('CHLD', noop)
        old_ttou = Kernel.trap('TTOU', 'IGNORE')
        old_ttin = Kernel.trap('TTIN', 'IGNORE')

        # Give terminal control to the pipeline's process group
        Terminal.set_foreground(pgid) if Terminal.tty?

        begin
          # Wait for all forked children and collect statuses
          statuses = pids.map do |pid|
            _, status = Process.wait2(pid, Process::WUNTRACED)
            stopped = true if status.stopped?
            status
          end
        ensure
          # Take back terminal control BEFORE any output
          Terminal.set_foreground(shell_pgid) if Terminal.tty?

          # Restore signal handlers
          Kernel.trap('CHLD', old_chld || 'DEFAULT')
          Kernel.trap('TTOU', old_ttou || 'DEFAULT')
          Kernel.trap('TTIN', old_ttin || 'DEFAULT')
        end
      else
        # Wait for all forked children and collect statuses
        statuses = pids.map do |pid|
          Process.wait(pid)
          $?
        end
      end

      # If any process was stopped (Ctrl-Z), add the pipeline as a stopped job
      if job_control && stopped && pgid
        command_str = @commands.map { |c| c.respond_to?(:name) ? ([c.name] + c.args).join(' ') : c.to_s }.join(' | ')
        job = JobManager.instance.add(
          pid: pgid,
          pgid: pgid,
          command: command_str
        )
        job.status = :stopped
        puts "\n[#{job.id}]+  Stopped                 #{command_str}"
      end

      # Add last command status if using lastpipe
      statuses << last_status if use_lastpipe && last_status

      @statuses = statuses
      @status = determine_pipeline_status(statuses)
      self
    end

    def run_with_block(block)
      # Set up pipes between commands, with last one going to a pipe we read
      pipes = @commands.length.times.map { IO.pipe }

      pids = @commands.each_with_index.map do |cmd, i|
        # Set stdin from previous pipe (except first command)
        cmd.stdin ||= pipes[i - 1][0] if i > 0

        # Set stdout to next pipe
        cmd.stdout ||= pipes[i][1]
        cmd.pipe_stdout = pipes[i][1]

        fork do
          # Close unused pipe ends
          pipes.each_with_index do |(reader, writer), j|
            if j == i - 1
              writer.close
            elsif j == i
              reader.close
            else
              reader.close
              writer.close
            end
          end

          Command.apply_child_redirections(*cmd.effective_streams)

          # Set prefix environment variables (e.g., FOO=bar cmd)
          cmd.prefix_env&.each { |k, v| ENV[k] = v } if cmd.respond_to?(:prefix_env)

          # Handle different command types
          if cmd.is_a?(Subshell)
            # Run subshell block
            result = cmd.instance_variable_get(:@block).call
            result.run if result.is_a?(Command) || result.is_a?(Pipeline)
            exit(result.respond_to?(:success?) && result.success? ? 0 : 0)
          elsif cmd.is_a?(HeredocCommand)
            # Run heredoc command in child process
            cmd.run
            exit(cmd.success? ? 0 : 1)
          elsif Command.function?(cmd.name)
            result = Command.call_function(cmd.name, cmd.args)
            exit(result ? 0 : 1)
          else
            Command.safe_exec(cmd.name, cmd.name, *cmd.args, fd_options: Command.child_fd_options(cmd.fd_redirects))
          end
        end
      end

      # Parent closes write ends
      pipes.each { |_, writer| writer.close }

      # Close intermediate read ends
      pipes[0...-1].each { |reader, _| reader.close }

      # Read from last pipe and yield to block
      last_reader = pipes.last[0]
      last_reader.each_line do |line|
        block.call(line.chomp)
      end
      last_reader.close

      # Wait for all children and collect statuses
      statuses = pids.map do |pid|
        Process.wait(pid)
        $?
      end
      @statuses = statuses
      @status = determine_pipeline_status(statuses)
      self
    end

    def determine_pipeline_status(statuses)
      return statuses.last unless Builtins.set_option?('pipefail')

      # With pipefail, return rightmost non-zero exit status
      failed = statuses.reverse.find { |s| !s.success? }
      failed || statuses.last
    end
  end

  class Subshell
    # The streams the subshell runs with, `>&2` and `2>&1` resolved in the
    # order the redirections were written (see Command#effective_streams).
    # A pipe assigned by Pipeline has no sequence number, so it counts as
    # the earliest redirection: `{ ...; } 2>&1 | cmd` sends stderr down
    # the pipe.
    def effective_streams
      out, err = @stdout, @stderr
      if out == :stderr && err == :stdout
        # Each dup takes the other stream as it was at that point: after
        # `2>&1 1>&2` both go where stdout went (the pipe, or stdout itself);
        # after `1>&2 2>&1` both go to stderr
        if (@stderr_seq || 0) < (@stdout_seq || 0)
          out = @pipe_stdout
          err = @pipe_stdout || :stdout
        else
          err = nil
        end
      end
      out = err if out == :stderr && err.is_a?(IO) && (@stderr_seq || 0) < (@stdout_seq || 0)
      err = @stdout if err == :stdout && @stdout.is_a?(IO) && (@stdout_seq || 0) < (@stderr_seq || 0)
      # In a pipeline the pipe was stdout before any redirection, so
      # `2>&1 >file` sends stderr down the pipe
      err = @pipe_stdout if err == :stdout && @pipe_stdout
      [@stdin, out, err]
    end

    def next_redirect_seq
      @redirect_seq = (@redirect_seq || 0) + 1
    end

    # Exit code for the value a subshell's block returned: an ExitStatus,
    # a ran Command/Pipeline, anything with success?, or 0.
    def self.exit_code_for(result)
      if result.respond_to?(:exitstatus) && result.exitstatus
        result.exitstatus
      elsif result.respond_to?(:status) && result.status.respond_to?(:exitstatus)
        ExitStatus.code_of(result.status)
      elsif result.respond_to?(:success?)
        result.success? ? 0 : 1
      else
        0
      end
    end

    attr_reader :status
    attr_accessor :stdin, :stdout, :stderr, :pipe_stdout

    def initialize(&block)
      @block = block
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @ran = false
      @noclobber_failed = false
      @restricted_failed = false
    end

    # Point the child's streams where the (resolved) redirections say. A
    # remaining :stdout / :stderr marker refers to the stream as it was
    # before the other one was redirected, so it is applied first.
    def self.apply_streams(stdin, stdout, stderr)
      $stdout.reopen($stderr) if stdout == :stderr
      $stderr.reopen($stdout) if stderr == :stdout
      [[$stdin, stdin], [$stdout, stdout], [$stderr, stderr]].each do |stream, target|
        if target == :closed
          stream.close
        elsif target.is_a?(IO)
          stream.reopen(target)
        end
      end
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      pid = fork do
        Subshell.apply_streams(*effective_streams)

        # The block contains __run_cmd calls which handle execution
        # So we just call the block and exit with the result's status
        result = @block.call
        exit(Subshell.exit_code_for(result))
      end

      @stdin&.close unless @stdin == $stdin || @stdin.is_a?(Symbol)
      @stdout&.close unless @stdout == $stdout || @stdout.is_a?(Symbol)

      Process.wait(pid)
      @status = $?
      self
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      if Builtins.set_option?('C') && File.file?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_clobber(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      @stdout_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_in(file)
      @stdin = File.open(file, 'r')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      @stderr_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'a')
      @stderr_seq = next_redirect_seq
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_to_out
      @stderr = :stdout
      @stderr_seq = next_redirect_seq
      self
    end

    def dup_out(target)
      case target
      when '1' then self
      when '2' then @stdout = :stderr; @stdout_seq = next_redirect_seq; self
      when '-' then @stdout = :closed; @stdout_seq = next_redirect_seq; self
      else redirect_out(target)
      end
    end

    def dup_in(target)
      case target
      when '0' then self
      when '-' then @stdin = :closed; self
      else redirect_in(target)
      end
    end

    def dup_err(target)
      case target
      when '1' then @stderr = :stdout; @stderr_seq = next_redirect_seq; self
      when '2' then self
      when '-' then @stderr = :closed; @stderr_seq = next_redirect_seq; self
      else redirect_err(target)
      end
    end

    # `(cmd) N>file` for N >= 3. Subshell/HeredocCommand currently
    # accept the call so codegen-emitted .fd_redirect(...) doesn't blow
    # up, but applying the redirect inside the forked subshell needs
    # in-process fd manipulation that isn't wired up yet — only the
    # plain Command case (which uses Kernel#exec's fd_options) honors
    # N>file. See ast.rb / generate_fd_redirect.
    def fd_redirect(_fd, _op, _target)
      self
    end
  end

  # Wrapper for heredoc/herestring that provides content as stdin
  class HeredocCommand
    # Same interface as Command#effective_streams, for pipelines mixing kinds
    def effective_streams
      err = @stderr
      err = @pipe_stdout if err == :stdout && @pipe_stdout && @stdout.equal?(@pipe_stdout)
      [@stdin, @stdout, err]
    end

    attr_reader :status
    attr_accessor :stdin, :stdout, :stderr, :pipe_stdout

    # compound: the block is a compound command (brace group, loop,
    # conditional) that runs when called, rather than one that builds a
    # Command or Pipeline to run afterwards
    def initialize(content, compound: false, &block)
      @content = content
      @block = block
      @compound = compound
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @ran = false
      @noclobber_failed = false
      @restricted_failed = false
    end

    def ran?
      @ran
    end

    def success?
      @status&.success? || false
    end

    def run
      return self if @ran
      @ran = true

      if @noclobber_failed
        @status = NoclobberStatus.new
        return self
      end

      if @restricted_failed
        @status = RestrictedStatus.new
        return self
      end

      return run_compound if @compound

      cmd = @block.call
      if cmd.is_a?(Command) || cmd.is_a?(Pipeline)
        # Create a pipe for heredoc content
        reader, writer = IO.pipe
        writer.write(@content)
        writer.close

        if cmd.is_a?(Command) && Builtins.builtin?(cmd.name)
          # Builtins run in-process and read from $stdin directly.
          # Temporarily redirect $stdin to the pipe so the builtin sees the content.
          original_stdin = $stdin.dup
          saved_out, saved_err = $stdout, $stderr
          # The command's own output redirections apply to the builtin and to
          # anything it runs (a mapfile -C callback, for instance)
          _, out, err = effective_streams
          begin
            $stdin.reopen(reader)
            case out
            when IO then $stdout = out
            when :stderr then $stdout = saved_err
            end
            case err
            when IO then $stderr = err
            when :stdout then $stderr = saved_out
            end
            prefix = cmd.respond_to?(:prefix_env) ? cmd.prefix_env : nil
            success = Builtins.with_temporary_vars(prefix) { Builtins.run(cmd.name, cmd.args) }
            exit_code = success.is_a?(ExitStatus) ? success.exitstatus : (success ? 0 : 1)
            @status = ExitStatus.new(exit_code)
          ensure
            [$stdout, $stderr].each { |io| io.flush if io.respond_to?(:flush) && !io.closed? }
            $stdout, $stderr = saved_out, saved_err
            $stdin.reopen(original_stdin)
            original_stdin.close
            reader.close unless reader.closed?
          end
        else
          # Set stdin from heredoc content
          cmd.stdin = reader

          # Apply any additional redirects we have
          cmd.stdout = @stdout if @stdout
          cmd.stderr = @stderr if @stderr

          cmd.run
          reader.close unless reader.closed?
          @status = cmd.status
        end
      end
      self
    end

    # A compound command runs in the shell process, so the content becomes
    # the shell's stdin for the duration: builtins such as `read` see it,
    # and so do external commands in the body, which inherit fd 0.
    def run_compound
      content_file = Command.content_file(@content)

      original_stdin = $stdin.dup
      saved_out, saved_err = $stdout, $stderr
      _, out, err = effective_streams
      begin
        $stdin.reopen(content_file)
        case out
        when IO then $stdout = out
        when :stderr then $stdout = saved_err
        end
        case err
        when IO then $stderr = err
        when :stdout then $stderr = saved_out
        end
        result = @block.call
        @status = ExitStatus.new(Subshell.exit_code_for(result))
      ensure
        [$stdout, $stderr].each { |io| io.flush if io.respond_to?(:flush) && !io.closed? }
        $stdout, $stderr = saved_out, saved_err
        $stdin.reopen(original_stdin)
        original_stdin.close
        content_file.close
      end
      self
    end

    def |(other)
      Pipeline.new(self, other)
    end

    def redirect_out(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      if Builtins.set_option?('C') && File.file?(file)
        $stderr.puts "rubish: #{file}: cannot overwrite existing file"
        @noclobber_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_clobber(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'w')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stdout = File.open(file, 'a')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_in(file)
      # For heredoc, stdin comes from content, so this is ignored
      self
    end

    def redirect_err(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'w')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_append(file)
      if Builtins.restricted_mode?
        $stderr.puts 'rubish: restricted: cannot redirect output'
        @restricted_failed = true
        return self
      end
      @stderr = File.open(file, 'a')
      self
    rescue SystemCallError => e
      $stderr.puts "rubish: #{file}: #{e.class.new.message}"
      @restricted_failed = true
      self
    end

    def redirect_err_to_out
      @stderr = :stdout
      self
    end

    def dup_out(target)
      case target
      when '1' then self
      when '2' then @stdout = :stderr; self
      when '-' then @stdout = :closed; self
      else redirect_out(target)
      end
    end

    def dup_in(target)
      case target
      when '0' then self
      when '-' then @stdin = :closed; self
      else redirect_in(target)
      end
    end

    def dup_err(target)
      case target
      when '1' then @stderr = :stdout; self
      when '2' then self
      when '-' then @stderr = :closed; self
      else redirect_err(target)
      end
    end

    # `(cmd) N>file` for N >= 3. Subshell/HeredocCommand currently
    # accept the call so codegen-emitted .fd_redirect(...) doesn't blow
    # up, but applying the redirect inside the forked subshell needs
    # in-process fd manipulation that isn't wired up yet — only the
    # plain Command case (which uses Kernel#exec's fd_options) honors
    # N>file. See ast.rb / generate_fd_redirect.
    def fd_redirect(_fd, _op, _target)
      self
    end
  end
end
