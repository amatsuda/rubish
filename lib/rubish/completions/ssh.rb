# frozen_string_literal: true

module Rubish
  module Builtins
    # ==========================================================================
    # SSH completion function
    # ==========================================================================
    def _ssh_completion(cmd, cur, prev)
      case prev
      when '-F', '-i', '-S', '-E', '-c', '-o'
        # File/config completions
        if %w[-F -i -S -E].include?(prev)
          _filedir([])
        else
          @compreply = []
        end
        return
      when '-l'
        # Username completion
        _usergroup(['-u'])
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

    def _ssh_complete_hosts(cur)
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
  end
end
