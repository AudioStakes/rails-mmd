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

  it 'fails before repair when a staged file also has unstaged changes' do
    in_git_repository do
      commit_example_file
      stage_then_edit_example_file

      expect { described_class.ensure_no_mixed_changes!(%w[example.rb]) }.to raise_error(SystemExit)
    end
  end

  it 'fails after repair when tracked files changed without staging' do
    in_git_repository do
      commit_example_file
      File.write('example.rb', "puts 'repair'\n")

      expect { described_class.ensure_no_post_repair_diff!(%w[example.rb]) }.to raise_error(SystemExit)
    end
  end

  it 'keeps the pre-commit hook order repair-first without automatic restaging' do
    expect_repair_first_order
    expect(lefthook_config_text).not_to match(/stage_fixed|git add/)
  end
end
