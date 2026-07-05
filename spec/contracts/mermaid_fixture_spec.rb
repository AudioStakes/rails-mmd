# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'P0 Mermaid golden fixtures' do
  def fixture_root
    Pathname(__dir__).join('../../fixtures/mermaid').expand_path
  end

  it 'compares golden Mermaid fixture text byte-for-byte' do
    expected_fixtures.each do |file_name, expected|
      expect(fixture_root.join(file_name).binread).to eq(expected)
    end
  end

  it 'keeps Mermaid CLI validation deferred and out of the repository' do
    expect(node_manifest_paths.select(&:exist?)).to be_empty
  end

  def node_manifest_paths
    %w[package.json package-lock.json yarn.lock pnpm-lock.yaml].map do |path|
      Pathname(path)
    end
  end

  def expected_fixtures
    {
      'er_direction.mmd' => er_direction_fixture,
      'er_markers_pk_fk.mmd' => er_markers_fixture,
      'er_attributes_none.mmd' => er_attributes_none_fixture,
      'class_direction_and_labels.mmd' => class_direction_fixture,
      'class_standalone_and_comments.mmd' => class_standalone_fixture
    }
  end

  def er_direction_fixture
    <<~MMD
      erDiagram
        direction LR
        USER
        ACCOUNT
    MMD
  end

  def er_markers_fixture
    <<~MMD
      erDiagram
        direction LR
        USER }o..|| ACCOUNT : account
        USER {
          bigint id PK
          bigint account_id FK
        }
        ACCOUNT {
          bigint id PK
        }
    MMD
  end

  def er_attributes_none_fixture
    <<~MMD
      erDiagram
        direction TB
        USER
        ACCOUNT
        USER |o..o{ ACCOUNT : account
    MMD
  end

  def class_direction_fixture
    <<~MMD
      classDiagram
        direction BT
        class ORDER
        class ACCOUNT
        ORDER "0..1" --> "0..*" ACCOUNT : billing_account
    MMD
  end

  def class_standalone_fixture
    <<~MMD
      classDiagram
        direction LR
        %% sanitized comment without sensitive data or paths
        class USER
        class ACCOUNT
    MMD
  end
end
# rubocop:enable RSpec/DescribeClass
