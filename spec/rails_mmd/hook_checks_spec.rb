# frozen_string_literal: true

require 'rails_mmd/hook_checks'
require 'tmpdir'
require 'yaml'

RSpec.describe RailsMmd::HookChecks do
  def system!(*command)
    system(*command, out: File::NULL, err: File::NULL) || raise("command failed: #{command.join(' ')}")
  end

  def in_git_repository
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        system!('git', 'init')
        system!('git', 'config', 'user.email', 'test@example.com')
        system!('git', 'config', 'user.name', 'Test User')
        yield dir
      end
    end
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

    described_class.run_targeted_specs!(%w[spec/example_spec.rb lib/example.rb])

    expect(Kernel).to have_received(:exec).with('bundle', 'exec', 'rspec', 'spec/example_spec.rb')
  end

  it 'reports when no direct spec files are present' do
    expect { described_class.run_targeted_specs!(%w[lib/example.rb]) }
      .to output("targeted specs: no direct spec files matched\n").to_stdout
  end

  it 'routes schema and fixture changes to contract specs' do
    command = pre_commit_commands.fetch('schema-fixture-routing')

    expect(command.fetch('run')).to eq('bundle exec rspec spec/contracts')
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
