# frozen_string_literal: true

require 'rails_mmd/verification_runner'
require 'stringio'
require 'tmpdir'
require 'yaml'

# rubocop:disable Lint/ConstantDefinitionInBlock, Metrics/MethodLength, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
RSpec.describe RailsMmd::VerificationRunner do
  Status = Struct.new(:success?)

  class RecordingProcess
    attr_reader :commands
    attr_accessor :capture_stderr, :capture_stdout, :diff_quiet, :failure

    def initialize
      @commands = []
      @capture_stdout = ''
      @capture_stderr = ''
      @diff_quiet = true
    end

    def run!(*command)
      commands << command
      raise RailsMmd::VerificationRunner::CommandFailed, 'recorded failure' if failure == command
    end

    def capture3(*command)
      commands << command
      [capture_stdout, capture_stderr, Status.new(capture_stderr.empty?)]
    end

    def success?(*command)
      commands << command
      diff_quiet
    end
  end

  class GitProcess < RailsMmd::VerificationRunner::ProcessAdapter
    attr_reader :commands

    def initialize(repair: nil)
      @commands = []
      @repair = repair
    end

    def run!(*command)
      commands << command
      @repair&.call if command.include?('--autocorrect-all')
    end
  end

  class SystemProcess < RailsMmd::VerificationRunner::ProcessAdapter
    def initialize(command_success)
      @command_success = command_success
    end

    def system(*)
      @command_success
    end
  end

  subject(:routing) { described_class.new(process: process, output: output, error: error) }

  let(:process) { RecordingProcess.new }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  describe RailsMmd::VerificationRunner::ProcessAdapter do
    it 'returns when the command succeeds' do
      adapter = SystemProcess.new(true)

      expect(adapter.run!('true')).to be_nil
    end

    it 'raises a command failure when the command fails' do
      adapter = SystemProcess.new(false)

      expect { adapter.run!('false') }
        .to raise_error(RailsMmd::VerificationRunner::CommandFailed, 'verification command failed: false')
    end
  end

  it 'runs the complete repair-first sequence and mutually exclusive routes once' do
    routing.run!(full_path_set)

    expect(process.commands).to eq(expected_full_commands)
    expect(output.string).to include('no P0 contract verifier exists yet')
  end

  it 'runs direct specs without the full coverage suite' do
    routing.run!(%w[spec/example_spec.rb spec/spec_helper.rb])

    expect(process.commands).to include(%w[bundle exec rspec spec/example_spec.rb])
    expect(process.commands).not_to include(%w[bundle exec rake coverage])
  end

  it 'prefers the full coverage suite when direct specs and coverage configuration overlap' do
    routing.run!(%w[spec/example_spec.rb .rspec])

    expect(process.commands).to include(%w[bundle exec rake coverage])
    expect(process.commands).not_to include(%w[bundle exec rspec spec/example_spec.rb])
  end

  it 'preserves spaced filenames as argv entries' do
    routing.run!(['lib/space name.rb'])

    expect(process.commands.first).to eq(['git', 'diff', '--name-only', '--', 'lib/space name.rb'])
    expect(process.commands[1].last).to eq('lib/space name.rb')
  end

  it 'blocks repair when a staged Ruby path also has unstaged changes' do
    process.capture_stdout = "lib/example.rb\n"

    expect { routing.run!(%w[lib/example.rb]) }.to raise_error(SystemExit)
    expect(error.string).to include('lib/example.rb', 'Stage or stash')
    expect(process.commands).to eq([%w[git diff --name-only -- lib/example.rb]])
  end

  it 'blocks read-only checks when repair changes tracked files' do
    process.diff_quiet = false

    expect { routing.run!(%w[lib/example.rb]) }.to raise_error(SystemExit)
    expect(error.string).to include('repair changed tracked files')
    expect(process.commands).to eq(
      [
        %w[git diff --name-only -- lib/example.rb],
        %w[bundle exec rubocop --autocorrect-all --force-exclusion -- lib/example.rb],
        %w[git diff --quiet]
      ]
    )
  end

  it 'maps failed verification commands to one quiet hook failure' do
    process.failure = %w[bundle exec rspec spec/example_spec.rb]

    expect { routing.run!(%w[spec/example_spec.rb]) }.to raise_error(SystemExit)
    expect(error.string).to eq("recorded failure\n")
  end

  it 'keeps Lefthook as a single adapter to the routing interface' do
    commands = YAML.safe_load_file('lefthook.yml').fetch('pre-commit').fetch('commands')

    expect(commands.keys).to eq(['verification-runner'])
    expect(commands.fetch('verification-runner').fetch('run')).to include('VerificationRunner.new.run!(ARGV)')
  end

  it 'limits the Lefthook adapter to the union of verification paths' do
    adapter = YAML.safe_load_file('lefthook.yml').fetch('pre-commit').fetch('commands').fetch('verification-runner')

    expect(adapter.fetch('glob')).to match_array(activation_globs)
  end

  it 'preserves every Ruby, dependency, and contract path family' do
    routing.run!(representative_paths)

    expect(process.commands).to include(
      ['bundle', 'exec', 'rubocop', '--force-exclusion', '--', *representative_ruby_paths],
      %w[bundle check],
      %w[bundle exec rspec spec/contracts]
    )
    expect(process.commands.count { |command| command == %w[bundle exec rspec spec/contracts] }).to eq(1)
  end

  it 'runs the repair-first path against an isolated real Git repository' do
    in_git_repository do
      commit_example_files
      stage_example_change

      expect { real_git_routing.run!(%w[example.rb]) }.not_to raise_error
    end
  end

  it 'detects mixed changes in an isolated real Git repository' do
    in_git_repository do
      commit_example_files
      stage_example_change
      File.write('example.rb', "puts 'unstaged'\n")

      expect { real_git_routing.run!(%w[example.rb]) }.to raise_error(SystemExit)
    end
  end

  it 'detects repair drift outside the staged paths in an isolated real Git repository' do
    in_git_repository do
      commit_example_files
      stage_example_change
      repair = -> { File.write('other.rb', "puts 'repair'\n") }

      expect { real_git_routing(repair: repair).run!(%w[example.rb]) }.to raise_error(SystemExit)
    end
  end

  def full_path_set
    %w[
      lib/example.rb spec/example_spec.rb .rspec Gemfile .ruby-version .rubocop.yml
      schemas/config.schema.json docs/p0-contract.md
    ]
  end

  def expected_full_commands
    ruby_path = %w[lib/example.rb spec/example_spec.rb]
    [
      ['git', 'diff', '--name-only', '--', *ruby_path],
      ['bundle', 'exec', 'rubocop', '--autocorrect-all', '--force-exclusion', '--', *ruby_path],
      %w[git diff --quiet],
      ['bundle', 'exec', 'rubocop', '--force-exclusion', '--', *ruby_path],
      %w[bundle exec rake coverage],
      %w[bundle check],
      %w[bundle exec rake bundle:audit],
      %w[ruby -v],
      %w[bundle exec exe/rails-mmd --version],
      %w[bundle exec rake rubocop],
      %w[bundle exec rspec spec/contracts]
    ]
  end

  def activation_globs
    %w[
      *.rb *.rake Rakefile exe/rails-mmd bin/**/* lib/**/*.rb spec/*.rb spec/**/*.rb
      features/*.rb features/**/*.rb .rspec .simplecov .undercover.yml Gemfile Gemfile.lock
      *.gemspec .ruby-version .rubocop.yml schemas/*.json schemas/**/*.json fixtures/*.json
      fixtures/**/*.json fixtures/*.mmd fixtures/**/*.mmd AGENTS.md README.md docs/*.md docs/**/*.md
    ]
  end

  def representative_paths
    representative_ruby_paths + %w[
      rails-mmd.gemspec README.md AGENTS.md schemas/nested/config.json
      fixtures/example.json fixtures/example.mmd fixtures/nested/example.json docs/nested/example.md
    ]
  end

  def representative_ruby_paths
    %w[
      root.rb task.rake Rakefile exe/rails-mmd bin/tool lib/example.rb
      spec/example.rb spec/unit/example_spec.rb features/example.rb features/unit/example.rb
    ]
  end

  def real_git_routing(repair: nil)
    described_class.new(process: GitProcess.new(repair: repair), output: output, error: error)
  end

  def in_git_repository(&block)
    outer_state = outer_repository_state
    ClimateControl.modify(git_repository_env.to_h { |key| [key, nil] }) { in_temporary_git_repository(&block) }
  ensure
    expect(outer_repository_state).to eq(outer_state) if outer_state
  end

  def in_temporary_git_repository
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        system!('git', 'init')
        system!('git', 'config', 'user.email', 'test@example.com')
        system!('git', 'config', 'user.name', 'Test User')
        yield dir
      end
    end
  end

  def git_repository_env
    %w[GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES]
  end

  def outer_repository_state
    head = Open3.capture2('git', 'rev-parse', 'HEAD').first
    tracked = Open3.capture2('git', 'status', '--porcelain', '--untracked-files=no').first
    [head, tracked]
  end

  def system!(*command)
    system(*command, out: File::NULL, err: File::NULL) || raise("command failed: #{command.join(' ')}")
  end

  def commit_example_files
    File.write('example.rb', "puts 'original'\n")
    File.write('other.rb', "puts 'original'\n")
    system!('git', 'add', 'example.rb', 'other.rb')
    system!('git', 'commit', '-m', 'initial')
  end

  def stage_example_change
    File.write('example.rb', "puts 'staged'\n")
    system!('git', 'add', 'example.rb')
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock, Metrics/MethodLength, RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/LeakyConstantDeclaration, RSpec/MultipleExpectations
