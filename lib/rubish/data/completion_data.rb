# frozen_string_literal: true

module Rubish
  module Builtins
    # Git commands for completion
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

    # Action flags mapping for complete/compgen builtins
    # Maps single-letter flags to their action symbols
    COMPLETION_ACTION_FLAGS = {
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
    }.freeze
  end
end
