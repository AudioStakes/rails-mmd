# frozen_string_literal: true

require 'rails_mmd/hook_checks'
require 'tmpdir'
require 'yaml'

RSpec.describe RailsMmd::HookChecks do
  def system!(*command)
    system(*command, out: File::NULL, err: File::NULL) || raise("command failed: #{command.join(' ')}")
  end

  def in_git_repository(&block)
    outer_state = outer_repository_state

    ClimateControl.modify(git_repository_env.to_h { |key| [key, nil] }) do
      in_temporary_git_repository(&block)
    end
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

  def commit_example_file
    File.write('example.rb', "puts 'original'\n")
    system!('git', 'add', 'example.rb')
    system!('git', 'commit', '-m', 'initial')
  end

  def stage_then_edit_example_file
    File.write('example.rb', "puts 'staged'\n")
    system!('git', 'add', 'example.rb')
    File.write('example.rb', "puts 'unstaged'\n")
  end

  def commit_spaced_file
    File.write('space name.rb', "puts 'original'\n")
    system!('git', 'add', 'space name.rb')
    system!('git', 'commit', '-m', 'spaced')
  end

  def stage_then_edit_spaced_file
    File.write('space name.rb', "puts 'staged'\n")
    system!('git', 'add', 'space name.rb')
    File.write('space name.rb', "puts 'unstaged'\n")
  end

  def commit_other_file
    File.write('other.rb', "puts 'original'\n")
    system!('git', 'add', 'other.rb')
    system!('git', 'commit', '-m', 'other')
  end

  def modify_other_file
    File.write('other.rb', "puts 'repair'\n")
  end

  def create_other_file_repair_drift
    commit_example_file
    commit_other_file
    modify_other_file
  end

  def command_names
    YAML.safe_load_file('lefthook.yml').fetch('pre-commit').fetch('commands').keys
  end

  def lefthook_config_text
    YAML.safe_load_file('lefthook.yml').to_s
  end

  def expect_repair_first_order
    expect(command_names).to include(*repair_first_commands)
    expect(repair_first_indexes).to eq([0, 1, 2, 3])
    expect(repair_first_priorities).to eq([1, 2, 3, 4])
  end

  def pre_commit_commands
    YAML.safe_load_file('lefthook.yml').fetch('pre-commit').fetch('commands')
  end

  def repair_first_commands
    %w[ruby-staged-safety ruby-rubocop-autocorrect ruby-post-repair-diff ruby-rubocop]
  end

  def repair_first_indexes
    repair_first_commands.map { |command| command_names.index(command) }
  end

  def repair_first_priorities
    repair_first_commands.map { |command| pre_commit_commands.fetch(command).fetch('priority') }
  end

  def rubocop_command(name)
    pre_commit_commands.fetch(name).fetch('run')
  end

  def ruby_specs_command
    pre_commit_commands.fetch('ruby-specs')
  end

  def rubocop_config_command
    pre_commit_commands.fetch('rubocop-config')
  end

  def contract_command
    pre_commit_commands.fetch('contract-routing')
  end

  def expected_contract_globs
    %w[
      schemas/*.json schemas/**/*.json
      fixtures/*.json fixtures/**/*.json fixtures/*.mmd fixtures/**/*.mmd
      AGENTS.md README.md docs/*.md docs/**/*.md
    ]
  end

  it 'fails before repair when a staged file also has unstaged changes' do
    in_git_repository do
      commit_example_file
      stage_then_edit_example_file

      expect { described_class.ensure_no_mixed_changes!(%w[example.rb]) }.to raise_error(SystemExit)
    end
  end

  it 'preserves spaced filenames when checking mixed changes' do
    in_git_repository do
      commit_spaced_file
      stage_then_edit_spaced_file

      expect { described_class.ensure_no_mixed_changes!(['space name.rb']) }.to raise_error(SystemExit)
    end
  end

  it 'fails after repair when tracked files changed without staging' do
    in_git_repository do
      commit_example_file
      File.write('example.rb', "puts 'repair'\n")

      expect { described_class.ensure_no_post_repair_diff! }.to raise_error(SystemExit)
    end
  end

  it 'fails after repair when a tracked file outside the staged list changed' do
    in_git_repository do
      create_other_file_repair_drift

      expect { described_class.ensure_no_post_repair_diff! }.to raise_error(SystemExit)
    end
  end

  it 'runs direct spec files when staged specs are present' do
    allow(Kernel).to receive(:exec)

    described_class.run_pre_commit_specs!(%w[spec/example_spec.rb lib/example.rb])

    expect(Kernel).to have_received(:exec).with('bundle', 'exec', 'rspec', 'spec/example_spec.rb')
  end

  it 'reports when no direct spec files are present' do
    expect { described_class.run_pre_commit_specs!(%w[spec/spec_helper.rb]) }
      .to output("targeted specs: no direct spec files matched\n").to_stdout
  end

  %w[.rspec .simplecov .undercover.yml].each do |config_path|
    it "runs the full coverage suite once when #{config_path} is staged" do
      allow(Kernel).to receive(:exec)

      described_class.run_pre_commit_specs!([config_path])

      expect(Kernel).to have_received(:exec).once.with('bundle', 'exec', 'rake', 'coverage')
    end
  end

  it 'prefers the full coverage suite when a direct spec and config overlap' do
    allow(Kernel).to receive(:exec)

    described_class.run_pre_commit_specs!(%w[spec/example_spec.rb .rspec])

    expect(Kernel).to have_received(:exec).once.with('bundle', 'exec', 'rake', 'coverage')
  end

  it 'routes direct specs and full-suite config through one pre-commit command' do
    expected_globs = %w[spec/*.rb spec/**/* .rspec .simplecov .undercover.yml]

    expect(ruby_specs_command.fetch('glob')).to match_array(expected_globs)
  end

  it 'uses the mutually exclusive pre-commit spec router' do
    expect(ruby_specs_command.fetch('run')).to include('run_pre_commit_specs!')
  end

  it 'removes the overlapping RSpec and coverage configuration command' do
    expect(command_names).not_to include('rubocop-rspec-coverage-config')
  end

  it 'routes RuboCop configuration without rerunning the coverage suite' do
    expect(rubocop_config_command.fetch('run')).to eq('bundle exec rake rubocop')
  end

  it 'limits RuboCop configuration routing to the RuboCop config' do
    expect(rubocop_config_command.fetch('glob')).to eq(['.rubocop.yml'])
  end

  it 'reports pending schema and fixture checks for matching paths' do
    expect { described_class.schema_fixture_pending!(%w[schemas/config.schema.json fixtures/mermaid/er.mmd]) }
      .to output("schema/fixture checks pending: schemas/config.schema.json, fixtures/mermaid/er.mmd\n").to_stdout
  end

  it 'routes schema and fixture changes to contract specs' do
    expect(contract_command.fetch('run')).to eq('bundle exec rspec spec/contracts')
  end

  it 'triggers one contract route for schema, fixture, and setup documentation paths' do
    expect(contract_command.fetch('glob')).to match_array(expected_contract_globs)
  end

  it 'defines the contract suite command only once' do
    contract_runs = pre_commit_commands.values.count { |command| command.fetch('run').include?('rspec spec/contracts') }

    expect(contract_runs).to eq(1)
  end

  it 'separates RuboCop options from staged file arguments' do
    expect(%w[ruby-rubocop-autocorrect ruby-rubocop].map { |name| rubocop_command(name) })
      .to all(include('--force-exclusion -- {staged_files}'))
  end

  it 'keeps the pre-commit hook order repair-first without automatic restaging' do
    expect_repair_first_order
    expect(lefthook_config_text).not_to match(/stage_fixed|git add/)
  end
end
