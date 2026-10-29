# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'rails_mmd/output_directory'

# rubocop:disable-next RSpec/ExampleLength, RSpec/InstanceVariable, RSpec/MultipleExpectations
RSpec.describe RailsMmd::OutputDirectory do
  around do |example|
    Dir.mktmpdir do |root|
      @project_root = Pathname(root)
      example.run
    end
  end

  let(:project_root) { @project_root }
  let(:output_directory) { described_class.new(project_root: project_root) }

  it 'publishes into a root-contained name beginning with two dots' do
    result = output_directory.resolve('..diagrams')

    output_directory.publish!(result, selected_domain_ids: ['core']) { { 'core.er.mmd' => 'new mermaid' } }

    expect(project_root.join('..diagrams/core.er.mmd').read).to eq('new mermaid')
    expect(output_directory.resolve('..diagrams')).to be_valid
  end

  it 'reconciles only the selected managed publication set' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.diagnostics.json').write('stale')
    output.join('admin.er.mmd').write('unselected')
    output.join('core.er.json').write('lookalike user file')
    output.join('notes.txt').write('user file')

    output_directory.publish!(
      output_directory.resolve('out'),
      selected_domain_ids: ['core']
    ) { { 'core.er.mmd' => 'new mermaid' } }

    expect(output.join('core.diagnostics.json')).not_to exist
    expect(output.join('core.er.mmd').read).to eq('new mermaid')
    expect(output.join('admin.er.mmd').read).to eq('unselected')
    expect(output.join('core.er.json').read).to eq('lookalike user file')
    expect(output.join('notes.txt').read).to eq('user file')
  end

  it 'rejects unsafe plan paths before writing outside the output directory' do
    result = output_directory.resolve('out')

    expect do
      output_directory.publish!(result, selected_domain_ids: ['core']) { { '../outside.mmd' => 'unsafe' } }
    end.to raise_error(ArgumentError, 'output plan path is unmanaged')
    expect(project_root.join('outside.mmd')).not_to exist
  end

  it 'rejects lookalike names that are not publishable artifact paths' do
    result = output_directory.resolve('out')

    expect do
      output_directory.publish!(result, selected_domain_ids: ['core']) { { 'core.er.json' => 'unsafe' } }
    end.to raise_error(ArgumentError, 'output plan path is unmanaged')
    expect(project_root.join('out/core.er.json')).not_to exist
  end

  it 'rejects near-miss managed filenames that are outside the publication contract' do
    result = output_directory.resolve('out')

    expect do
      output_directory.publish!(result, selected_domain_ids: ['core']) { { 'core.er.json' => 'unsafe' } }
    end.to raise_error(ArgumentError, 'output plan path is unmanaged')

    expect do
      output_directory.publish!(result, selected_domain_ids: ['core']) { { 'global.diagnostics.mmd' => 'unsafe' } }
    end.to raise_error(ArgumentError, 'output plan path is unmanaged')
  end

  it 'refuses symlink targets before changing the existing managed set' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.diagnostics.json').write('old diagnostics')
    File.symlink(project_root.join('outside.mmd'), output.join('core.er.mmd'))

    expect do
      output_directory.publish!(
        output_directory.resolve('out'),
        selected_domain_ids: ['core']
      ) { { 'core.er.mmd' => 'new mermaid' } }
    end.to raise_error(ArgumentError, 'output target is symlink')
    expect(output.join('core.diagnostics.json').read).to eq('old diagnostics')
    expect(output.join('core.er.mmd')).to be_symlink
  end

  it 'rechecks a resolved ancestor before creating the output directory' do
    result = output_directory.resolve('link/artifacts')
    Dir.mktmpdir do |outside_root|
      outside = Pathname(outside_root)
      File.symlink(outside, project_root.join('link'))

      expect do
        output_directory.publish!(result, selected_domain_ids: ['core']) { { 'core.er.mmd' => 'new mermaid' } }
      end.to raise_error(ArgumentError, 'output path escapes project root')
      expect(outside.join('artifacts')).not_to exist
    end
  end

  it 'restores already-backed-up files when backup fails mid-publication' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').write('old mermaid')
    output.join('core.er.render_plan.json').write('old plan')
    fail_second_backup_move

    expect do
      output_directory.publish!(output_directory.resolve('out'), selected_domain_ids: ['core']) do
        {
          'core.er.mmd' => 'new mermaid',
          'core.er.render_plan.json' => 'new plan'
        }
      end
    end.to raise_error(Errno::EACCES)
    expect(output.join('core.er.mmd').read).to eq('old mermaid')
    expect(output.join('core.er.render_plan.json').read).to eq('old plan')
    expect(output.children.map { |path| path.basename.to_s }).not_to include(a_string_starting_with('.rails-mmd-'))
  end

  it 'rolls back the managed set when replacement fails mid-publication' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').write('old mermaid')
    output.join('core.er.render_plan.json').write('old plan')
    fail_render_plan_move_once

    expect do
      output_directory.publish!(
        output_directory.resolve('out'),
        selected_domain_ids: ['core']
      ) do
        {
          'core.er.mmd' => 'new mermaid',
          'core.er.render_plan.json' => 'new plan'
        }
      end
    end.to raise_error(Errno::EACCES)
    expect(output.join('core.er.mmd').read).to eq('old mermaid')
    expect(output.join('core.er.render_plan.json').read).to eq('old plan')
    expect(output.children.map { |path| path.basename.to_s }).not_to include(a_string_starting_with('.rails-mmd-'))
  end

  it 'retains recoverable originals inside the output directory when rollback also fails' do
    output = project_root.join('out')
    output.mkpath
    output.join('core.er.mmd').write('old mermaid')
    output.join('core.er.render_plan.json').write('old plan')
    fail_replacement_and_rollback_moves

    expect do
      output_directory.publish!(output_directory.resolve('out'), selected_domain_ids: ['core']) do
        {
          'core.er.mmd' => 'new mermaid',
          'core.er.render_plan.json' => 'new plan'
        }
      end
    end.to raise_error(Errno::EACCES)

    backups = output.children.select { |path| path.basename.to_s.start_with?('.rails-mmd-backup-') }
    expect(backups.length).to eq(1)
    expect(backups.first.stat.mode & 0o077).to eq(0)
    expect(backups.first.join('core.er.mmd').read).to eq('old mermaid')
    expect(backups.first.join('core.er.render_plan.json').read).to eq('old plan')

    allow(FileUtils).to receive(:mv).and_call_original
    output_directory.publish!(output_directory.resolve('out'), selected_domain_ids: ['core']) do
      { 'core.er.mmd' => 'retried mermaid' }
    end

    expect(output.join('core.er.mmd').read).to eq('retried mermaid')
    expect(backups.first.join('core.er.mmd').read).to eq('old mermaid')
    expect(backups.first.join('core.er.render_plan.json').read).to eq('old plan')
    expect(output.children.select { |path| path.basename.to_s.start_with?('.rails-mmd-') }).to eq(backups)
  end

  def fail_render_plan_move_once
    failed = false
    allow(FileUtils).to receive(:mv).and_wrap_original do |method, source, target|
      if !failed && target.end_with?('/out/core.er.render_plan.json')
        failed = true
        raise Errno::EACCES, source
      end

      method.call(source, target)
    end
  end

  def fail_replacement_and_rollback_moves
    allow(FileUtils).to receive(:mv).and_wrap_original do |method, source, target|
      if source.include?('/.rails-mmd-backup-') || target.end_with?('/out/core.er.render_plan.json')
        raise Errno::EACCES, source
      end

      method.call(source, target)
    end
  end

  def fail_second_backup_move
    backup_moves = 0
    allow(FileUtils).to receive(:mv).and_wrap_original do |method, source, target|
      if target.include?('/.rails-mmd-backup-')
        backup_moves += 1
        raise Errno::EACCES, source if backup_moves == 2
      end

      method.call(source, target)
    end
  end
end
