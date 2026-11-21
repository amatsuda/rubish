# frozen_string_literal: true

module Rubish
  module Builtins
    def pushd(args)
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
        if @state.dir_stack.empty?
          puts 'pushd: no other directory'
          return false
        end
        current = logical_pwd
        target = @state.dir_stack.shift
        @state.dir_stack.unshift(current)
        return false unless no_cd || chdir_safe(target, 'pushd')
        print_dir_stack
        true
      elsif remaining_args.first =~ /^[+-]\d+$/
        # Stack rotation: +N or -N
        arg = remaining_args.first
        n = arg[1..].to_i
        full_stack = [logical_pwd] + @state.dir_stack

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
        @state.dir_stack = rotated[1..]

        return false unless no_cd || chdir_safe(target, 'pushd')
        print_dir_stack
        true
      else
        # Push directory
        dir = remaining_args.first
        dir = File.expand_path(dir)
        current = logical_pwd

        unless File.directory?(dir)
          puts "pushd: #{dir}: No such file or directory"
          return false
        end

        @state.dir_stack.unshift(current)
        return false unless no_cd || chdir_safe(dir, 'pushd')
        print_dir_stack
        true
      end
    end

    def popd(args)
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

      if @state.dir_stack.empty? && index_arg.nil?
        puts 'popd: directory stack empty'
        return false
      end

      full_stack = [logical_pwd] + @state.dir_stack

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
          @state.dir_stack = full_stack[2..] || []
          return false unless no_cd || chdir_safe(target, 'popd')
        else
          # Removing from stack (not current dir)
          full_stack.delete_at(index)
          @state.dir_stack = full_stack[1..] || []
        end
      else
        # Default: pop top of stack and cd there
        if @state.dir_stack.empty?
          puts 'popd: directory stack empty'
          return false
        end

        target = @state.dir_stack.shift
        return false unless no_cd || chdir_safe(target, 'popd')
      end

      print_dir_stack
      true
    end

    def dirs(args)
      clear   = false
      long    = false
      per_line = false
      verbose  = false
      index_arg = nil

      expanded = []
      args.each do |arg|
        if arg =~ /\A-([clpv]+)\z/
          $1.each_char { |c| expanded << "-#{c}" }
        else
          expanded << arg
        end
      end

      expanded.each do |arg|
        case arg
        when '-c' then clear = true
        when '-l' then long = true
        when '-p' then per_line = true
        when '-v' then verbose = true
        when /\A[+-]\d+\z/ then index_arg = arg
        else
          $stderr.puts "dirs: #{arg}: invalid option"
          return false
        end
      end

      if clear
        @state.dir_stack.clear
        return true
      end

      home  = ENV['HOME'] || Dir.home
      stack = [logical_pwd] + @state.dir_stack

      # Tildify only when $HOME is a real path prefix — never anywhere
      # mid-path. Plain `dir.sub(home, '~')` would rewrite
      # `/tmp/Users/joe/sub` (HOME=/Users/joe) to `/tmp~/sub`, which
      # is not what bash does.
      tildify = ->(dir) {
        return dir if long || home.nil? || home.empty?
        return dir.sub(home, '~') if dir == home || dir.start_with?("#{home}/")
        dir
      }

      format_entry = ->(dir, idx) {
        display = tildify.call(dir)
        verbose ? format('%2d  %s', idx, display) : display
      }

      if index_arg
        n = index_arg[1..].to_i
        idx = index_arg.start_with?('+') ? n : stack.length - 1 - n
        if idx < 0 || idx >= stack.length
          $stderr.puts "dirs: #{index_arg}: directory stack index out of range"
          return false
        end
        puts format_entry.call(stack[idx], idx)
        return true
      end

      if verbose || per_line
        stack.each_with_index { |d, i| puts format_entry.call(d, i) }
      else
        puts stack.map { |d| tildify.call(d) }.join(' ')
      end

      true
    end

    def print_dir_stack
      home = ENV['HOME'] || Dir.home
      stack = [logical_pwd] + @state.dir_stack
      puts stack.map { |d| d.sub(home, '~') }.join(' ')
    end

    def clear_dir_stack
      @state.dir_stack.clear
    end

    private

    # The current directory as the shell names it: $PWD while it still points
    # at the physical cwd (keeps symlinks such as /tmp), else the physical path
    def logical_pwd
      ENV['PWD'] && File.identical?(ENV['PWD'], Dir.pwd) ? ENV['PWD'] : Dir.pwd
    end

    # Change directory the way cd does: keep the logical path and update
    # OLDPWD and PWD, so `pwd` and prompts follow pushd/popd
    def chdir_safe(target, cmd_name)
      base = logical_pwd
      logical = File.expand_path(target, base)
      Dir.chdir(logical)
      ENV['OLDPWD'] = base
      ENV['PWD'] = logical
      notify_terminal_of_cwd
      true
    rescue Errno::ENOENT => e
      puts "#{cmd_name}: #{e.message}"
      false
    end
  end
end
