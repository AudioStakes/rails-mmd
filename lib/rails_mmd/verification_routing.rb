# frozen_string_literal: true

require 'open3'

module RailsMmd
  # Owns pre-commit path classification, ordering, and command selection.
  class VerificationRouting
    class CommandFailed < StandardError; end

    RUBY_PATH = %r{
      \A(?:
        [^/]+\.(?:rb|rake)|Rakefile|exe/rails-mmd|bin/.+|lib/.+\.rb|
        spec/(?:.+/)?[^/]+\.rb|features/(?:.+/)?[^/]+\.rb
      )\z
    }x
    DIRECT_SPEC_PATH = %r{\Aspec/.+_spec\.rb\z}
    FULL_SPEC_SUITE_CONFIG_PATHS = %w[.rspec .simplecov .undercover.yml].freeze
    DEPENDENCY_PATH = %r{\A(?:Gemfile(?:\.lock)?|[^/]+\.gemspec)\z}
    CONTRACT_PATH = %r{\A(?:schemas/.+\.json|fixtures/.+\.(?:json|mmd)|AGENTS\.md|README\.md|docs/.+\.md)\z}

    # The process seam has a production adapter and recording adapters in specs.
    class ProcessAdapter
      def run!(*command)
        return if system(*command)

        raise CommandFailed, "verification command failed: #{command.join(' ')}"
      end

      def capture3(*command)
        Open3.capture3(*command)
      end

      def success?(*command)
        system(*command, out: File::NULL, err: File::NULL)
      end
    end

    def initialize(process: ProcessAdapter.new, output: $stdout, error: $stderr)
      @process = process
      @output = output
      @error = error
    end

    def run!(paths)
      route(normalize_paths(paths))
    rescue CommandFailed => e
      error.puts(e.message)
      raise SystemExit, 1
    end

    private

    attr_reader :error, :output, :process

    def route(paths)
      run_ruby_checks(paths.grep(RUBY_PATH))
      run_specs(paths)
      run_dependency_checks(paths)
      run_ruby_version_smoke(paths)
      run_rubocop_config(paths)
      run_contracts(paths)
      report_p0_contract(paths)
    end

    def normalize_paths(paths)
      paths.flatten.compact.map(&:to_s).reject(&:empty?).uniq
    end

    def run_ruby_checks(paths)
      return if paths.empty?

      ensure_no_mixed_changes!(paths)
      process.run!('bundle', 'exec', 'rubocop', '--autocorrect-all', '--force-exclusion', '--', *paths)
      ensure_no_post_repair_diff!
      process.run!('bundle', 'exec', 'rubocop', '--force-exclusion', '--', *paths)
    end

    def ensure_no_mixed_changes!(paths)
      mixed_paths = unstaged_changed_paths(paths)
      return if mixed_paths.empty?

      report_mixed_paths(mixed_paths)
      raise SystemExit, 1
    end

    def unstaged_changed_paths(paths)
      stdout, stderr, status = process.capture3('git', 'diff', '--name-only', '--', *paths)
      raise CommandFailed, stderr unless status.success?

      stdout.lines.map(&:chomp).reject(&:empty?)
    end

    def report_mixed_paths(mixed_paths)
      error.puts('pre-commit blocked: these staged files also have unstaged changes:')
      mixed_paths.each { |path| error.puts("  #{path}") }
      error.puts('Stage or stash the unstaged changes before repair commands run.')
    end

    def ensure_no_post_repair_diff!
      return if process.success?('git', 'diff', '--quiet')

      error.puts('pre-commit blocked: repair changed tracked files.')
      error.puts('Inspect the deterministic repair diff, then stage the intended changes.')
      raise SystemExit, 1
    end

    def run_specs(paths)
      if paths.intersect?(FULL_SPEC_SUITE_CONFIG_PATHS)
        process.run!('bundle', 'exec', 'rake', 'coverage')
      elsif (specs = paths.grep(DIRECT_SPEC_PATH)).any?
        process.run!('bundle', 'exec', 'rspec', *specs)
      end
    end

    def run_dependency_checks(paths)
      return unless paths.any? { |path| path.match?(DEPENDENCY_PATH) }

      process.run!('bundle', 'check')
      process.run!('bundle', 'exec', 'rake', 'bundle:audit')
    end

    def run_ruby_version_smoke(paths)
      return unless paths.include?('.ruby-version')

      process.run!('ruby', '-v')
      process.run!('bundle', 'exec', 'exe/rails-mmd', '--version')
    end

    def run_rubocop_config(paths)
      process.run!('bundle', 'exec', 'rake', 'rubocop') if paths.include?('.rubocop.yml')
    end

    def run_contracts(paths)
      process.run!('bundle', 'exec', 'rspec', 'spec/contracts') if paths.any? { |path| path.match?(CONTRACT_PATH) }
    end

    def report_p0_contract(paths)
      return unless paths.include?('docs/p0-contract.md')

      output.puts('docs/p0-contract.md changed; no P0 contract verifier exists yet.')
    end
  end
end
