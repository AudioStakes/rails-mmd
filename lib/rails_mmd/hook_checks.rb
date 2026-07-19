# frozen_string_literal: true

require 'open3'

module RailsMmd
  # Small Git-state checks used by Lefthook pre-commit commands.
  module HookChecks
    FULL_SPEC_SUITE_CONFIG_PATHS = %w[.rspec .simplecov .undercover.yml].freeze

    module_function

    def ensure_no_mixed_changes!(paths)
      paths = normalize_paths(paths)
      return puts('staged safety: no matching staged files') if paths.empty?

      mixed_paths = unstaged_changed_paths(paths)
      return puts('staged safety: no mixed staged/unstaged files') if mixed_paths.empty?

      warn 'pre-commit blocked: these staged files also have unstaged changes:'
      mixed_paths.each { |path| warn "  #{path}" }
      warn 'Stage or stash the unstaged changes before repair commands run.'
      exit 1
    end

    def ensure_no_post_repair_diff!
      return puts('post-repair diff: no tracked repair diff') if git_success?('diff', '--quiet')

      warn 'pre-commit blocked: repair changed tracked files.'
      warn 'Inspect the deterministic repair diff, then stage the intended changes.'
      exit 1
    end

    def run_pre_commit_specs!(paths)
      paths = normalize_paths(paths)
      return Kernel.exec 'bundle', 'exec', 'rake', 'coverage' if paths.intersect?(FULL_SPEC_SUITE_CONFIG_PATHS)

      specs = paths.grep(%r{\Aspec/.+_spec\.rb\z})
      return puts('targeted specs: no direct spec files matched') if specs.empty?

      Kernel.exec 'bundle', 'exec', 'rspec', *specs
    end

    def schema_fixture_pending!(paths)
      paths = normalize_paths(paths)
      puts "schema/fixture checks pending: #{paths.join(', ')}"
    end

    def normalize_paths(paths)
      paths.flatten.compact.map(&:to_s).reject(&:empty?).uniq
    end

    def unstaged_changed_paths(paths)
      stdout, stderr, status = Open3.capture3('git', 'diff', '--name-only', '--', *paths)
      abort stderr unless status.success?

      stdout.lines.map(&:chomp).reject(&:empty?)
    end

    def git_success?(*)
      system('git', *, out: File::NULL, err: File::NULL)
    end
  end
end
