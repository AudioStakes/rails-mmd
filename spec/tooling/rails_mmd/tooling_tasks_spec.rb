# frozen_string_literal: true

require_relative '../../../tooling/tooling_tasks'

RSpec.describe RailsMmd::ToolingTasks do
  describe '.undercover_compare_ref' do
    before do
      allow(described_class).to receive(:git_ref?).and_return(false)
      allow(described_class).to receive(:git_ref?).with('HEAD~1').and_return(true)
    end

    it 'uses the configured comparison when no override is provided', env: { 'UNDERCOVER_COMPARE' => nil } do
      expect(described_class.undercover_compare_ref('HEAD~1')).to eq('HEAD~1')
    end

    it 'uses a valid explicit comparison instead of the configured default',
       env: { 'UNDERCOVER_COMPARE' => 'feature/base' } do
      allow(described_class).to receive(:git_ref?).with('feature/base').and_return(true)

      expect(described_class.undercover_compare_ref('HEAD~1')).to eq('feature/base')
    end

    it 'rejects an invalid explicit comparison even when the default exists',
       env: { 'UNDERCOVER_COMPARE' => 'missing/base' } do
      expect { described_class.undercover_compare_ref('HEAD~1') }
        .to raise_error(SystemExit, 'UNDERCOVER_COMPARE does not resolve to a commit: "missing/base"')
    end

    it 'rejects an empty explicit comparison', env: { 'UNDERCOVER_COMPARE' => '' } do
      expect { described_class.undercover_compare_ref('HEAD~1') }
        .to raise_error(SystemExit, 'UNDERCOVER_COMPARE does not resolve to a commit: ""')
    end

    it 'falls back to a main ref when the configured default is unavailable', env: { 'UNDERCOVER_COMPARE' => nil } do
      allow(described_class).to receive(:git_ref?).with('origin/main').and_return(true)

      expect(described_class.undercover_compare_ref('missing/default')).to eq('origin/main')
    end

    it 'reports when none of the automatic comparison refs are available', env: { 'UNDERCOVER_COMPARE' => nil } do
      expect(described_class.undercover_compare_ref('missing/default')).to be_nil
    end
  end
end
