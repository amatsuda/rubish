# frozen_string_literal: true

module Rubish
  # Prompt handling for the shell REPL
  # Supports bash-style (\X) and zsh-style (%X) prompt escapes
  module Prompt
    # Zsh color name to number mapping
    ZSH_COLORS = {'black' => 0, 'red' => 1, 'green' => 2, 'yellow' => 3, 'blue' => 4, 'magenta' => 5, 'cyan' => 6, 'white' => 7, 'default' => 9}.freeze

    def self.included(base)
      base.class_eval do
        class << self
          attr_accessor :prompt_proc, :right_prompt_proc
        end
      end
    end

    def prompt
      # First check for fish-style prompt function
      if self.class.prompt_proc
        begin
          return instance_exec(&self.class.prompt_proc)
        rescue => e
          $stderr.puts "rubish: prompt error: #{e.message}"
        end
      end

      # Fall back to bash/zsh-style environment variables
      ps1 = ENV['PS1'] || ENV['PROMPT']
      if ps1
        expand_prompt(ps1)
      else
        # Default prompt
        "#{Dir.pwd.sub(ENV['HOME'], '~')}$ "
      end
    end

    def continuation_prompt
      ps2 = ENV['PS2']
      if ps2
        expand_prompt(ps2)
      else
        '> '
      end
    end

    # Right prompt (like zsh's RPROMPT)
    def right_prompt
      # First check for fish-style right prompt function
      if self.class.right_prompt_proc
        begin
          result = instance_exec(&self.class.right_prompt_proc)
          return result unless result.nil? || result.empty?
        rescue => e
          $stderr.puts "rubish: right_prompt error: #{e.message}"
        end
      end

      # Fall back to bash/zsh-style environment variables
      rprompt = ENV['RPROMPT'] || ENV['RPS1']
      return nil unless rprompt && !rprompt.empty?

      expand_prompt(rprompt)
    end

    # Set Reline's rprompt for right-side prompt display
    def setup_rprompt
      Reline.rprompt = right_prompt
    end

    # Calculate visible length of a string (excluding ANSI escape codes)
    def visible_length(str)
      # Remove ANSI escape sequences
      str.gsub(/\e\[[0-9;]*[a-zA-Z]/, '').length
    end

    # Get terminal width
    def terminal_width
      if $stdout.tty?
        begin
          _rows, cols = $stdout.winsize
          cols
        rescue
          ENV['COLUMNS']&.to_i || 80
        end
      else
        80
      end
    end

    def expand_prompt(ps)
      result = +''
      i = 0

      while i < ps.length
        if ps[i] == '\\'
          # Bash-style escapes: \X
          i += 1
          break if i >= ps.length

          case ps[i]
          when 'a'
            result << "\a"
          when 'd'
            result << Time.now.strftime('%a %b %d')
          when 'D'
            # \D{format} - custom strftime format
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              fmt_end = ps.index('}', i)
              if fmt_end
                fmt = ps[i...fmt_end]
                result << Time.now.strftime(fmt)
                i = fmt_end
              end
            else
              i -= 1  # Back up, wasn't \D{...}
              result << 'D'
            end
          when 'e'
            result << "\e"
          when 'h'
            result << Socket.gethostname.split('.').first
          when 'H'
            result << Socket.gethostname
          when 'j'
            result << JobManager.instance.active.count.to_s
          when 'l'
            result << (File.basename(`tty`.strip) rescue 'tty')
          when 'n'
            result << "\n"
          when 'r'
            result << "\r"
          when 's'
            result << 'rubish'
          when 't'
            result << Time.now.strftime('%H:%M:%S')
          when 'T'
            result << Time.now.strftime('%I:%M:%S')
          when '@'
            result << Time.now.strftime('%I:%M %p')
          when 'A'
            result << Time.now.strftime('%H:%M')
          when 'u'
            result << (ENV['USER'] || Etc.getlogin || 'user')
          when 'v'
            result << Rubish::VERSION
          when 'V'
            result << Rubish::VERSION
          when 'w'
            home = ENV['HOME'] || ''
            cwd = Dir.pwd
            display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
            result << trim_prompt_dir(display_path)
          when 'W'
            cwd = Dir.pwd
            home = ENV['HOME'] || ''
            if cwd == home
              result << '~'
            else
              result << File.basename(cwd)
            end
          when '!'
            result << (Reline::HISTORY.length + 1).to_s
          when '#'
            result << (@command_number || 1).to_s
          when '$'
            result << (Process.uid == 0 ? '#' : '$')
          when '\\'
            result << '\\'
          when '['
            # Begin non-printing sequence (for terminal escape codes)
            # We just skip this marker
          when ']'
            # End non-printing sequence
            # We just skip this marker
          when '0', '1', '2', '3', '4', '5', '6', '7'
            # Octal character \nnn
            octal = ps[i]
            while i + 1 < ps.length && ps[i + 1] =~ /[0-7]/ && octal.length < 3
              i += 1
              octal << ps[i]
            end
            result << octal.to_i(8).chr
          else
            # Unknown escape, keep literal
            result << '\\' << ps[i]
          end
          i += 1
        elsif ps[i] == '%'
          # Zsh-style escapes: %X
          i += 1
          break if i >= ps.length

          case ps[i]
          when 'n'
            result << (ENV['USER'] || Etc.getlogin || 'user')
          when 'm'
            result << Socket.gethostname.split('.').first
          when 'M'
            result << Socket.gethostname
          when '~'
            home = ENV['HOME'] || ''
            cwd = Dir.pwd
            display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
            result << trim_prompt_dir(display_path)
          when '/'
            result << Dir.pwd
          when 'd'
            result << Dir.pwd
          when '.'
            # %. - basename like %1~
            cwd = Dir.pwd
            home = ENV['HOME'] || ''
            result << (cwd == home ? '~' : File.basename(cwd))
          when '1', '2', '3', '4', '5', '6', '7', '8', '9'
            # %N~ - last N path components
            n = ps[i].to_i
            i += 1
            if i < ps.length && ps[i] == '~'
              home = ENV['HOME'] || ''
              cwd = Dir.pwd
              display_path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
              components = display_path.split('/')
              if components.length > n
                result << components.last(n).join('/')
              else
                result << display_path
              end
            else
              i -= 1
              result << '%' << ps[i]
            end
          when 'T'
            result << Time.now.strftime('%H:%M')
          when 't', '@'
            result << Time.now.strftime('%I:%M %p')
          when '*'
            result << Time.now.strftime('%H:%M:%S')
          when 'D'
            # %D or %D{format}
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              fmt_end = ps.index('}', i)
              if fmt_end
                fmt = ps[i...fmt_end]
                result << Time.now.strftime(fmt)
                i = fmt_end
              end
            else
              i -= 1
              result << Time.now.strftime('%y-%m-%d')
            end
          when 'g'
            # %g - git prompt info (branch, status)
            result << git_prompt_info
          when 'p'
            # %p or %p{N} - abbreviated path (like fish's prompt_pwd)
            # N specifies expand_level (default 1)
            expand_level = 1
            if i + 1 < ps.length && ps[i + 1] == '{'
              i += 2
              level_end = ps.index('}', i)
              if level_end
                expand_level = ps[i...level_end].to_i
                expand_level = 1 if expand_level < 1
                i = level_end
              else
                i -= 2
              end
            end
            result << prompt_pwd(expand_level: expand_level)
          when 'j'
            result << JobManager.instance.active.count.to_s
          when '?'
            result << @last_status.to_s
          when '#'
            result << (Process.uid == 0 ? '#' : '%')
          when 'F'
            # %F{color} - foreground color
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              color_end = ps.index('}', i)
              if color_end
                color = ps[i...color_end]
                result << zsh_color_to_ansi(color, :fg)
                i = color_end
              end
            else
              i -= 1
            end
          when 'f'
            result << "\e[39m"  # Reset foreground
          when 'K'
            # %K{color} - background color
            i += 1
            if i < ps.length && ps[i] == '{'
              i += 1
              color_end = ps.index('}', i)
              if color_end
                color = ps[i...color_end]
                result << zsh_color_to_ansi(color, :bg)
                i = color_end
              end
            else
              i -= 1
            end
          when 'k'
            result << "\e[49m"  # Reset background
          when 'B'
            result << "\e[1m"   # Bold on
          when 'b'
            result << "\e[22m"  # Bold off
          when 'U'
            result << "\e[4m"   # Underline on
          when 'u'
            result << "\e[24m"  # Underline off
          when '%'
            result << '%'
          else
            # Unknown escape, keep literal
            result << '%' << ps[i]
          end
          i += 1
        else
          result << ps[i]
          i += 1
        end
      end

      # promptvars (bash) / prompt_subst (zsh): if enabled, perform variable and command substitution
      if Builtins.shopt_enabled?('promptvars') || Builtins.zsh_option_enabled?('prompt_subst')
        result = expand_string_content(result)
      end

      result
    end

    # Convert zsh color names/numbers to ANSI escape codes
    # Supports: color names (red, green, blue, etc.), 0-255 color numbers
    def zsh_color_to_ansi(color, type)
      base = type == :fg ? 30 : 40

      if color =~ /\A\d+\z/
        num = color.to_i
        if num < 8
          "\e[#{base + num}m"
        elsif num < 16
          # Bright colors (8-15)
          "\e[#{base + 60 + (num - 8)}m"
        else
          # 256-color mode
          "\e[#{type == :fg ? 38 : 48};5;#{num}m"
        end
      elsif ZSH_COLORS.key?(color.downcase)
        "\e[#{base + ZSH_COLORS[color.downcase]}m"
      else
        ''
      end
    end

    # Abbreviated path for prompts (like fish's prompt_pwd)
    # expand_level: number of trailing path components to show in full
    # Example with ~/src/github.com/amatsuda/rubish:
    #   prompt_pwd(expand_level: 1) => "~/s/g/a/rubish"
    #   prompt_pwd(expand_level: 2) => "~/s/g/amatsuda/rubish"
    def prompt_pwd(expand_level: 1)
      home = ENV['HOME'] || ''
      cwd = Dir.pwd
      path = home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')

      components = path.split('/')
      return path if components.length <= expand_level + 1

      # Handle leading empty string from absolute path or ~
      first = components.first
      rest = components[1..]

      # Number of components to abbreviate (all except the last expand_level)
      abbrev_count = rest.length - expand_level

      abbreviated = rest.take(abbrev_count).map { |c| c[0] || c }
      full = rest.drop(abbrev_count)

      ([first] + abbreviated + full).join('/')
    end

    # Color helper methods for prompts
    # These wrap text in ANSI escape codes for colorized output
    #
    # Usage with Rubish.set_prompt:
    #   Rubish.set_prompt { cyan(prompt_pwd) + " " + green(git_prompt_info) + "> " }

    def black(text);   "\e[30m#{text}\e[39m"; end
    def red(text);     "\e[31m#{text}\e[39m"; end
    def green(text);   "\e[32m#{text}\e[39m"; end
    def yellow(text);  "\e[33m#{text}\e[39m"; end
    def blue(text);    "\e[34m#{text}\e[39m"; end
    def magenta(text); "\e[35m#{text}\e[39m"; end
    def cyan(text);    "\e[36m#{text}\e[39m"; end
    def white(text);   "\e[37m#{text}\e[39m"; end

    # Bright/bold colors
    def bright_black(text);   "\e[90m#{text}\e[39m"; end
    def bright_red(text);     "\e[91m#{text}\e[39m"; end
    def bright_green(text);   "\e[92m#{text}\e[39m"; end
    def bright_yellow(text);  "\e[93m#{text}\e[39m"; end
    def bright_blue(text);    "\e[94m#{text}\e[39m"; end
    def bright_magenta(text); "\e[95m#{text}\e[39m"; end
    def bright_cyan(text);    "\e[96m#{text}\e[39m"; end
    def bright_white(text);   "\e[97m#{text}\e[39m"; end

    # Text styles
    def bold(text);      "\e[1m#{text}\e[22m"; end
    def dim(text);       "\e[2m#{text}\e[22m"; end
    def italic(text);    "\e[3m#{text}\e[23m"; end
    def underline(text); "\e[4m#{text}\e[24m"; end

    # Flexible color by name or number (0-255)
    def fg(color, text)
      code = color_to_code(color, :fg)
      "#{code}#{text}\e[39m"
    end

    def bg(color, text)
      code = color_to_code(color, :bg)
      "#{code}#{text}\e[49m"
    end

    # Prompt helper methods - Ruby equivalents of % escape sequences
    # These can be used in Rubish.set_prompt / Rubish.set_right_prompt blocks

    # %n - current username
    def current_username
      ENV['USER'] || Etc.getlogin || 'user'
    end

    # %m - short hostname (first component)
    def short_hostname
      Socket.gethostname.split('.').first
    end

    # %M - full hostname
    def full_hostname
      Socket.gethostname
    end

    # %~ - current directory with ~ substitution for home
    def current_directory
      home = ENV['HOME'] || ''
      cwd = Dir.pwd
      home.empty? ? cwd : cwd.sub(/\A#{Regexp.escape(home)}/, '~')
    end

    # %/ or %d - full current directory (no ~ substitution)
    def full_directory
      Dir.pwd
    end

    # %. - basename of current directory (~ if in home)
    def directory_basename
      cwd = Dir.pwd
      home = ENV['HOME'] || ''
      cwd == home ? '~' : File.basename(cwd)
    end

    # %j - number of background jobs
    def job_count
      JobManager.instance.active.count
    end

    # %? - exit status of last command
    def last_exit_status
      @last_status
    end

    # %# - privilege indicator (# for root, % for normal user)
    def privilege_indicator
      Process.uid == 0 ? '#' : '%'
    end

    # %! - current history number
    def history_number
      Reline::HISTORY.length + 1
    end

    # %i or \# - command number in this session
    def command_number
      @command_number || 1
    end

    # %D{format} - formatted date/time (strftime)
    def formatted_time(format = '%H:%M:%S')
      Time.now.strftime(format)
    end

    # %T - current time in 24-hour HH:MM format
    def time_24h
      Time.now.strftime('%H:%M')
    end

    # %t or %@ - current time in 12-hour with AM/PM
    def time_12h
      Time.now.strftime('%I:%M %p')
    end

    # %* - current time with seconds HH:MM:SS
    def time_with_seconds
      Time.now.strftime('%H:%M:%S')
    end

    # %D - current date in YY-MM-DD format
    def current_date
      Time.now.strftime('%y-%m-%d')
    end

    # %W - day of week (Sunday = 0)
    def day_of_week
      Time.now.wday
    end

    # %l - current tty
    def current_tty
      File.basename(`tty`.strip) rescue 'tty'
    end

    # %s - shell name
    def shell_name
      'rubish'
    end

    # %v - shell version
    def shell_version
      Rubish::VERSION
    end

    # Helper for superuser check
    def superuser?
      Process.uid == 0
    end

    # Git prompt info - returns formatted git status for use in prompts
    #
    # Keyword arguments (default to corresponding GIT_PS1_* env vars if not specified):
    #   dirty:      show * for unstaged, + for staged changes (GIT_PS1_SHOWDIRTYSTATE)
    #   stash:      show $ if stash is not empty (GIT_PS1_SHOWSTASHSTATE)
    #   untracked:  show % if there are untracked files (GIT_PS1_SHOWUNTRACKEDFILES)
    #   upstream:   show <, >, <>, = for behind/ahead/diverged/up-to-date (GIT_PS1_SHOWUPSTREAM)
    #   colorize:   colorize the output (GIT_PS1_SHOWCOLORHINTS)
    #   describe:   how to show detached HEAD: contains, branch, tag, describe, default (GIT_PS1_DESCRIBE_STYLE)
    #
    # Example:
    #   git_prompt_info(dirty: true, stash: true, untracked: true, upstream: true, colorize: true)
    def git_prompt_info(dirty: nil, stash: nil, untracked: nil, upstream: nil, colorize: nil, describe: nil)
      # Check if we're in a git repo
      git_dir = `git rev-parse --git-dir 2>/dev/null`.chomp
      return '' if git_dir.empty?

      # Resolve options: use kwarg if provided, otherwise fall back to env var
      show_dirty = dirty.nil? ? ENV['GIT_PS1_SHOWDIRTYSTATE'] : dirty
      show_stash = stash.nil? ? ENV['GIT_PS1_SHOWSTASHSTATE'] : stash
      show_untracked = untracked.nil? ? ENV['GIT_PS1_SHOWUNTRACKEDFILES'] : untracked
      show_upstream = upstream.nil? ? ENV['GIT_PS1_SHOWUPSTREAM'] : upstream
      show_colorize = colorize.nil? ? ENV['GIT_PS1_SHOWCOLORHINTS'] : colorize
      describe_style = describe || ENV['GIT_PS1_DESCRIBE_STYLE'] || 'default'

      # Get branch name or commit
      branch = `git symbolic-ref --short HEAD 2>/dev/null`.chomp
      if branch.empty?
        # Detached HEAD - show commit or tag
        branch = case describe_style.to_s
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
      return '' if branch.empty?

      state = +''

      # Show dirty state (* for unstaged, + for staged)
      if show_dirty
        # Check for staged changes
        staged = !`git diff --cached --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        # Check for unstaged changes
        unstaged = !`git diff --quiet 2>/dev/null; echo $?`.chomp.to_i.zero?
        state << '+' if staged
        state << '*' if unstaged
      end

      # Show stash state
      if show_stash
        stash_list = `git stash list 2>/dev/null`.chomp
        state << '$' unless stash_list.empty?
      end

      # Show untracked files
      if show_untracked
        untracked_files = `git ls-files --others --exclude-standard 2>/dev/null`.chomp
        state << '%' unless untracked_files.empty?
      end

      # Show upstream status
      upstream_str = ''
      if show_upstream
        counts = `git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null`.chomp.split
        if counts.length == 2
          ahead, behind = counts.map(&:to_i)
          if ahead > 0 && behind > 0
            upstream_str = '<>'
          elsif ahead > 0
            upstream_str = '>'
          elsif behind > 0
            upstream_str = '<'
          else
            upstream_str = '='
          end
        end
      end

      # Format output
      state_str = state.empty? ? '' : " #{state}"

      # Apply colors if enabled
      if show_colorize
        # Green for clean, red for dirty, yellow for staged only
        color_branch = if state.include?('*')
                         "\e[31m#{branch}\e[0m"  # Red for unstaged changes
                       elsif state.include?('+')
                         "\e[33m#{branch}\e[0m"  # Yellow for staged only
                       else
                         "\e[32m#{branch}\e[0m"  # Green for clean
                       end
        "(#{color_branch}#{state_str}#{upstream_str})"
      else
        "(#{branch}#{state_str}#{upstream_str})"
      end
    end

    # PS3 prompt for select command
    def select_prompt
      ps3 = ENV['PS3']
      if ps3
        expand_prompt(ps3)
      else
        '#? '
      end
    end

    # Print PS0 prompt (displayed after command is read, before execution)
    # PS0 supports the same escape sequences as PS1
    def print_ps0
      ps0 = ENV['PS0']
      return unless ps0 && !ps0.empty?

      print expand_prompt(ps0)
      $stdout.flush
    end

    # Execute PROMPT_COMMAND before displaying the prompt
    # PROMPT_COMMAND can be:
    #   - A single command string
    #   - Multiple commands separated by semicolons
    #   - An array of commands (PROMPT_COMMAND[0], PROMPT_COMMAND[1], etc.)
    def run_prompt_command
      # First check for PROMPT_COMMAND array
      prompt_cmds = Builtins.get_array('PROMPT_COMMAND')
      if prompt_cmds && !prompt_cmds.empty?
        prompt_cmds.each do |cmd|
          next if cmd.nil? || cmd.empty?
          execute_prompt_command(cmd)
        end
        return
      end

      # Fall back to PROMPT_COMMAND as a string
      cmd = ENV['PROMPT_COMMAND']
      return if cmd.nil? || cmd.empty?

      execute_prompt_command(cmd)
    end

    def execute_prompt_command(cmd)
      # Save current state
      saved_status = @last_status

      # Execute the command silently (don't affect $?)
      begin
        execute(cmd)
      rescue => e
        # Silently ignore errors in PROMPT_COMMAND
        $stderr.puts "rubish: PROMPT_COMMAND: #{e.message}" if Builtins.set_option?('x')
      end

      # Restore the exit status (PROMPT_COMMAND shouldn't affect $?)
      @last_status = saved_status
    end

    # Trim directory path according to PROMPT_DIRTRIM
    # When PROMPT_DIRTRIM is set to N, only show last N directory components
    # with leading "..." to indicate trimming
    def trim_prompt_dir(path)
      dirtrim = ENV['PROMPT_DIRTRIM']
      return path if dirtrim.nil? || dirtrim.empty?

      trim_count = dirtrim.to_i
      return path if trim_count <= 0

      # Handle ~ prefix specially
      if path.start_with?('~')
        if path == '~'
          return path
        end
        # Remove ~ prefix, process the rest
        rest = path[1..]  # includes leading /
        rest = rest[1..] if rest.start_with?('/')  # remove leading /
        components = rest.split('/')
        if components.length <= trim_count
          return path
        end
        trimmed = components.last(trim_count).join('/')
        return '~/.../' + trimmed
      else
        # Absolute or relative path
        components = path.split('/').reject(&:empty?)
        if components.length <= trim_count
          return path
        end
        trimmed = components.last(trim_count).join('/')
        return '.../' + trimmed
      end
    end

    private

    def color_to_code(color, type)
      base = type == :fg ? 30 : 40

      case color
      when Integer
        if color < 8
          "\e[#{base + color}m"
        elsif color < 16
          "\e[#{base + 60 + (color - 8)}m"
        else
          "\e[#{type == :fg ? 38 : 48};5;#{color}m"
        end
      when Symbol, String
        name = color.to_s.downcase
        if ZSH_COLORS.key?(name)
          "\e[#{base + ZSH_COLORS[name]}m"
        else
          ''
        end
      else
        ''
      end
    end
  end
end
