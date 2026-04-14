# frozen_string_literal: true

module Rubish
  module Builtins
    # ==========================================================================
    # Git completion function
    # ==========================================================================

    def _git_completion(cmd, cur, prev)
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

    def _git_complete_add(cur, prev)
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

    def _git_complete_branch(cur, prev)
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

    def _git_complete_checkout(cur, prev)
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

    def _git_complete_commit(cur, prev)
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

    def _git_complete_diff(cur, prev)
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

    def _git_complete_remote_branch(cur, prev, subcommand)
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

    def _git_complete_log(cur, prev)
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

    def _git_complete_remote(cur, prev, words, cword, subcommand_idx)
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

    def _git_complete_reset(cur, prev)
      if cur.start_with?('-')
        opts = %w[-q --quiet --soft --mixed --hard --merge --keep -p --patch -N
                  --intent-to-add --pathspec-from-file= --pathspec-file-nul]
        @compreply = opts.select { |opt| opt.start_with?(cur) }
      else
        _git_complete_refs(cur)
        _git_complete_files(cur)
      end
    end

    def _git_complete_stash(cur, prev, words, cword, subcommand_idx)
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

    def _git_complete_tag(cur, prev)
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

    def _git_complete_refs(cur)
      # Complete git refs (branches, tags, commits)
      @compreply ||= []
      return unless git_repo?

      begin
        # Get all refs
        refs = `git for-each-ref --format='%(refname:short)' 2>/dev/null`.split("\n")
        refs.concat(`git rev-parse --symbolic --branches --tags --remotes 2>/dev/null`.split("\n"))
        refs.uniq!
        @compreply.concat(refs.select { |r| r.start_with?(cur) })
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_local_branches(cur)
      @compreply = []
      return unless git_repo?

      begin
        branches = `git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null`.split("\n")
        @compreply = branches.select { |b| b.start_with?(cur) }
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_remote_refs(cur)
      @compreply = []
      return unless git_repo?

      begin
        refs = `git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null`.split("\n")
        @compreply = refs.select { |r| r.start_with?(cur) }
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_remotes(cur)
      @compreply ||= []
      return unless git_repo?

      begin
        remotes = `git remote 2>/dev/null`.split("\n")
        @compreply.concat(remotes.select { |r| r.start_with?(cur) })
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_tags(cur)
      @compreply ||= []
      return unless git_repo?

      begin
        tags = `git tag -l 2>/dev/null`.split("\n")
        @compreply.concat(tags.select { |t| t.start_with?(cur) })
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_stash_refs(cur)
      @compreply = []
      return unless git_repo?

      begin
        stashes = `git stash list 2>/dev/null`.each_line.map { |l| l.split(':').first }.compact
        @compreply = stashes.select { |s| s.start_with?(cur) }
      rescue Errno::ENOENT, IOError
        # Git command not found or I/O error
      end
    end

    def _git_complete_files(cur)
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
        rescue Errno::ENOENT, IOError
          # Git command not found or I/O error
        end
      end

      # Also complete regular files
      pattern = cur.empty? ? '*' : "#{cur}*"
      @compreply.concat(Dir.glob(pattern).select { |f| File.file?(f) || File.directory?(f) })
      @compreply.uniq!
    end

    def git_repo?
      system('git rev-parse --git-dir >/dev/null 2>&1')
    end
  end
end
