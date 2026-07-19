# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../tooling/rails_matrix'

# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Layout/HeredocIndentation
RSpec.describe 'the Rails compatibility matrix Rake command' do
  let(:matching_fake_app_asdf) { fake_generated_app_asdf }
  let(:matching_rails72_fake_app_asdf) do
    fake_generated_app_asdf(composite_habtm_probe: {
                              rails_version: '7.2.3.1',
                              book_sql_has_full_owner_tuple: false, book_sql_uses_scalar_fallback: true,
                              author_sql_has_full_owner_tuple: false, author_sql_uses_scalar_fallback: true
                            })
  end

  let(:invalid_artifact_asdf) do
    <<~'SH'
      [ "$1" = "where" ] && exit 0
      case "$*" in
        *--version*) exit 0 ;;
        *"exec rails-mmd generate"*)
          mkdir -p tmp/rails_mmd
          printf 'erDiagram\n' > tmp/rails_mmd/core.er.mmd
          printf 'classDiagram\n' > tmp/rails_mmd/core.class.mmd
          printf '{}\n' > tmp/rails_mmd/core.er.render_plan.json
          printf '{}\n' > tmp/rails_mmd/core.class.render_plan.json
          exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:selected_pair_asdf) do
    <<~SH
      [ "$1 $2 $3" = "where ruby 4.0.6" ] && exit 0
      [ "$1" = "where" ] && exit 1
      case "$*" in
        *--version*) exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  let(:malformed_mermaid_asdf) do
    fake_generated_app_asdf(actual_er_mermaid: "not mermaid\n", actual_class_mermaid: "not mermaid\n")
  end

  let(:missing_expected_diagnostics_asdf) do
    fake_generated_app_asdf(expected_diagnostics: '[{"code":"ASSOCIATION_MACRO_OMITTED"}]')
  end

  let(:unexpected_diagnostics_asdf) do
    fake_generated_app_asdf(actual_diagnostics_fixture: 'fixtures/schemas/diagnostics/valid/catalog.json')
  end

  let(:missing_expected_relationships_asdf) do
    fake_generated_app_asdf(expected_relationships: '[]')
  end

  it 'registers the specialized-options fixture family and runtime oracle' do
    manifest = RailsMatrix::Manifest.new(
      Pathname(__dir__).join('../../fixtures/rails_matrix/matrix.yml').expand_path
    )
    registration = {
      fixture_family: manifest.fixture_families.include?('specialized_options'),
      runtime_oracle: RailsMatrix::FAMILY_RUNTIME_ORACLES.key?('specialized_options')
    }

    expect(registration).to eq(fixture_family: true, runtime_oracle: true)
  end

  it 'registers the cross-domain multi-DB family, runtime oracle, and pair probe' do
    manifest = RailsMatrix::Manifest.new(
      Pathname(__dir__).join('../../fixtures/rails_matrix/matrix.yml').expand_path
    )
    registration = {
      fixture_family: manifest.fixture_families.include?('cross_domain_multi_db'),
      runtime_oracle: RailsMatrix::FAMILY_RUNTIME_ORACLES.key?('cross_domain_multi_db'),
      pair_probe: RailsMatrix::PAIR_PROBES.key?('cross_domain_multi_db')
    }

    expect(registration).to eq(fixture_family: true, runtime_oracle: true, pair_probe: true)
  end

  it 'accepts the closed connection-boundary probe evidence for a matrix pair' do
    pair = RailsMatrix::Pair.new(ruby_version: '4.0.6', rails_series: '8.1')

    expect do
      RailsMatrix::ConnectionBoundaryProbeValidator.new.validate(connection_boundary_probe_payload, pair)
    end.not_to raise_error
  end

  def missing_expected_polymorphic_groups_asdf
    fake_generated_app_asdf(expected_polymorphic_groups: <<~JSON.chomp)
      [
        {
          "group_id": "relationships/comments/polymorphic/commentable/commentable_id/commentable_type",
          "holder_safe_token": "COMMENT",
          "root_label": "commentable",
          "candidate_target_safe_tokens": ["IMAGE"],
          "foreign_key_attributes": ["commentable_id", "commentable_type"]
        }
      ]
    JSON
  end

  def changed_expected_scoped_metadata_asdf
    relationship = generic_expected_relationship.dup
    relationship.delete(:metadata)
    fake_generated_app_asdf(expected_relationships: JSON.pretty_generate([relationship]))
  end

  def missing_expected_habtm_asdf
    relationships = [generic_expected_relationship, habtm_expected_relationship]
    fake_generated_app_asdf(expected_relationships: JSON.pretty_generate(relationships))
  end

  def missing_expected_class_oracle_asdf
    fake_generated_app_asdf(expected_class_mermaid: nil)
  end

  def missing_expected_er_oracle_asdf
    fake_generated_app_asdf(expected_er_mermaid: nil)
  end

  def missing_expected_sti_entities_oracle_asdf
    fake_generated_app_asdf(expected_sti_entities: nil)
  end

  def mismatched_expected_class_oracle_asdf
    fake_generated_app_asdf(expected_class_mermaid: <<~MMD)
      classDiagram
        direction BT
        class ORDER
        class ACCOUNT
        class CUSTOMER
        ORDER "0..1" --> "0..*" ACCOUNT : billing_account
    MMD
  end

  def mismatched_expected_er_oracle_asdf
    fake_generated_app_asdf(expected_er_mermaid: <<~MMD)
      erDiagram
        direction LR
        %% sanitized comment
        USER }o..|| ACCOUNT : account
        USER {
          bigint id PK
          bigint account_id FK
        }
        ACCOUNT {
          bigint id PK
        }
        PROFILE {
          bigint id PK
        }
    MMD
  end

  def mismatched_expected_sti_entities_asdf
    entities = fake_sti_entities.map(&:dup)
    entities.first['label'] = 'Wrong::Car'
    fake_generated_app_asdf(
      actual_class_plan_fixture: 'fixtures/schemas/render_plan/valid/class_sti.json',
      actual_class_mermaid: fake_class_sti_mermaid,
      expected_class_mermaid: fake_class_sti_mermaid,
      expected_sti_entities: JSON.pretty_generate(entities)
    )
  end

  def mismatched_expected_inheritances_asdf
    inheritances = fake_sti_inheritances.map(&:dup)
    inheritances.first['parent_entity_id'] = 'entities/missing'
    fake_generated_app_asdf(
      actual_class_plan_fixture: 'fixtures/schemas/render_plan/valid/class_sti.json',
      actual_class_mermaid: fake_class_sti_mermaid,
      expected_class_mermaid: fake_class_sti_mermaid,
      expected_sti_entities: JSON.pretty_generate(fake_sti_entities),
      expected_inheritances: JSON.pretty_generate(inheritances)
    )
  end

  def mismatched_expected_sti_runtime_asdf
    runtime = fake_sti_runtime.map(&:dup)
    runtime.last['sti_name'] = 'WrongDog'
    fake_generated_app_asdf(
      actual_class_plan_fixture: 'fixtures/schemas/render_plan/valid/class_sti.json',
      actual_class_mermaid: fake_class_sti_mermaid,
      expected_class_mermaid: fake_class_sti_mermaid,
      expected_sti_entities: JSON.pretty_generate(fake_sti_entities),
      expected_inheritances: JSON.pretty_generate(fake_sti_inheritances),
      expected_runtime: JSON.pretty_generate(runtime),
      actual_runtime: JSON.pretty_generate(fake_sti_runtime)
    )
  end

  def missing_expected_delegated_runtime_asdf
    fake_generated_app_asdf(expected_delegated_runtime: nil)
  end

  def malformed_delegated_runtime_asdf
    fake_generated_app_asdf(actual_delegated_runtime: '{not-json')
  end

  def mismatched_expected_delegated_runtime_asdf
    fake_generated_app_asdf(expected_delegated_runtime: '[{"association_name":"wrong"}]')
  end

  def missing_expected_composite_runtime_asdf
    fake_generated_app_asdf(expected_composite_runtime: nil)
  end

  def malformed_composite_runtime_asdf
    fake_generated_app_asdf(actual_composite_runtime: '{not-json')
  end

  def mismatched_expected_composite_runtime_asdf
    fake_generated_app_asdf(expected_composite_runtime: '[{"ruby_constant":"Wrong"}]')
  end

  def missing_expected_specialized_options_runtime_asdf
    fake_generated_app_asdf(expected_specialized_options_runtime: nil)
  end

  def mismatched_expected_specialized_options_runtime_asdf
    fake_generated_app_asdf(expected_specialized_options_runtime: '[{"binding":"wrong"}]')
  end

  def failing_composite_habtm_probe_asdf
    fake_generated_app_asdf(
      composite_habtm_probe: {
        rails_version: '8.1.3',
        book_sql_has_full_owner_tuple: false,
        book_sql_uses_scalar_fallback: false,
        author_sql_has_full_owner_tuple: false,
        author_sql_uses_scalar_fallback: true
      }
    )
  end

  def connection_boundary_probe_payload
    {
      'rails_version' => '8.1.3',
      'reflections' => {
        'belongs_to' => {
          'klass' => 'P206Account', 'foreign_key' => 'account_id', 'association_primary_key' => 'id'
        },
        'has_many' => {
          'klass' => 'P206Audit', 'foreign_key' => 'account_id', 'association_primary_key' => 'id'
        }
      },
      'contexts' => {
        'primary' => {
          'name' => 'primary', 'role' => 'writing', 'shard' => 'default',
          'database' => '/tmp/probe/primary.sqlite3'
        },
        'archive' => {
          'name' => 'archive', 'role' => 'writing', 'shard' => 'default',
          'database' => '/tmp/probe/archive.sqlite3'
        },
        'reading' => {
          'name' => 'primary_replica', 'role' => 'reading', 'shard' => 'default',
          'database' => '/tmp/probe/primary.sqlite3'
        },
        'primary_vs_archive_same_database' => false,
        'primary_vs_archive_same_context' => false,
        'primary_vs_reading_same_database' => true,
        'primary_vs_reading_same_context' => false
      },
      'database_evidence' => {
        'primary_foreign_keys_for_archive_table' => 0,
        'archive_foreign_keys_for_owner_table' => 0
      },
      'identity_collision' => { 'same_table_name' => true, 'different_context_name' => true }
    }
  end

  def generic_expected_relationship
    {
      relationship_id: 'relationships/users/account', owner_safe_token: 'USER', target_safe_token: 'ACCOUNT',
      label: 'account', owner_cardinality: '0..many', target_cardinality: '1..1', metadata: { scoped: true }
    }
  end

  def generic_expected_entities
    [
      { entity_id: 'entities/users', entity_kind: 'physical', label: 'User', safe_token: 'USER' },
      { entity_id: 'entities/accounts', entity_kind: 'physical', label: 'Account', safe_token: 'ACCOUNT' }
    ]
  end

  def habtm_expected_relationship
    {
      relationship_id: 'relationships/authors/habtm/authors_tags/author_id/tags/tag_id',
      owner_safe_token: 'AUTHOR', target_safe_token: 'TAG', label: 'tags',
      owner_cardinality: '0..many', target_cardinality: '0..many'
    }
  end

  def fake_generated_app_asdf(
    actual_er_plan_fixture: 'fixtures/schemas/render_plan/valid/er.json',
    actual_class_plan_fixture: 'fixtures/schemas/render_plan/valid/class.json',
    expected_er_plan_fixture: actual_er_plan_fixture,
    expected_class_plan_fixture: actual_class_plan_fixture,
    actual_er_mermaid: fake_er_mermaid,
    actual_class_mermaid: fake_class_mermaid,
    expected_er_mermaid: fake_er_mermaid,
    expected_class_mermaid: fake_class_mermaid,
    expected_diagnostics: '[]',
    expected_relationships: JSON.pretty_generate([generic_expected_relationship]),
    expected_entities: JSON.pretty_generate(generic_expected_entities),
    expected_polymorphic_groups: '[]',
    expected_sti_entities: '[]',
    expected_inheritances: '[]',
    expected_runtime: '[]',
    actual_runtime: '[]',
    expected_delegated_runtime: '[]',
    actual_delegated_runtime: '[]',
    expected_composite_runtime: '[]',
    actual_composite_runtime: '[]',
    expected_specialized_options_runtime: '[]',
    actual_specialized_options_runtime: '[]',
    expected_cross_domain_runtime: '[]',
    actual_cross_domain_runtime: '[]',
    connection_boundary_probe: connection_boundary_probe_payload,
    success_extra_artifact: false,
    collision_extra_artifact: false,
    collision_leak: false,
    collision_expectation_mismatch: false,
    composite_habtm_probe: {
      rails_version: '8.1.3',
      book_sql_has_full_owner_tuple: false,
      book_sql_uses_scalar_fallback: true,
      author_sql_has_full_owner_tuple: false,
      author_sql_uses_scalar_fallback: true
    },
    actual_diagnostics_fixture:
      'fixtures/rails_matrix/template/families/cross_domain_multi_db/rails_mmd_empty_diagnostics_fixture.json'
  )
    <<~SH
      [ "$1" = "where" ] && exit 0
      case "$*" in
        *--version*) exit 0 ;;
        *"exec ruby bin/rails runner script/rails_mmd_sti_runtime_oracle.rb"*)
          mkdir -p tmp/rails_mmd
#{write_file_shell('tmp/rails_mmd/sti_runtime.json', actual_runtime)}          exit 0 ;;
        *"exec ruby bin/rails runner script/rails_mmd_delegated_type_runtime_oracle.rb"*)
          mkdir -p tmp/rails_mmd
#{write_file_shell('tmp/rails_mmd/delegated_type_runtime.json', actual_delegated_runtime)}          exit 0 ;;
        *"exec ruby bin/rails runner script/rails_mmd_composite_runtime_oracle.rb"*)
          mkdir -p tmp/rails_mmd
#{write_file_shell('tmp/rails_mmd/composite_runtime.json', actual_composite_runtime)}          exit 0 ;;
        *"exec ruby bin/rails runner script/rails_mmd_specialized_options_runtime_oracle.rb"*)
          mkdir -p tmp/rails_mmd
#{write_file_shell('tmp/rails_mmd/specialized_options_runtime.json', actual_specialized_options_runtime)}          exit 0 ;;
        *"exec ruby bin/rails runner script/rails_mmd_cross_domain_runtime_oracle.rb"*)
          mkdir -p tmp/rails_mmd
#{write_file_shell('tmp/rails_mmd/cross_domain_runtime.json', actual_cross_domain_runtime)}          exit 0 ;;
        *"composite_habtm_probe.rb"*)
          printf '%s\n' '-- create_table(:p204_books, {id: false})'
          printf '%s\n' '#{JSON.generate(composite_habtm_probe)}'
          exit 0 ;;
        *"connection_boundary_probe.rb"*)
          printf '%s\n' '#{JSON.generate(connection_boundary_probe)}'
          exit 0 ;;
        *"exec rails-mmd generate --config rails_mmd_collision.yml"*)
          mkdir -p tmp/rails_mmd_collision
          cp "$RAILS_MMD_TEST_ROOT/fixtures/rails_matrix/template/families/cross_domain_multi_db/rails_mmd_collision_diagnostics_fixture.json" tmp/rails_mmd_collision/collision.diagnostics.json
          #{'touch tmp/rails_mmd_collision/collision.er.mmd' if collision_extra_artifact}
          #{"sed -i '' 's#tmp/matrix_archive.sqlite3#/Users/secret/archive.sqlite3#' tmp/rails_mmd_collision/collision.diagnostics.json" if collision_leak}
          #{"printf '[]\\n' > rails_mmd_expected_collision_diagnostics.json" if collision_expectation_mismatch}
          exit 2 ;;
        *"exec rails-mmd generate"*)
#{write_file_shell('rails_mmd_expected_diagnostics.json', expected_diagnostics)}#{write_file_shell('rails_mmd_expected_relationships.json', expected_relationships)}#{write_file_shell('rails_mmd_expected_entities.json', expected_entities)}#{write_file_shell('rails_mmd_expected_polymorphic_groups.json', expected_polymorphic_groups)}#{write_file_shell('rails_mmd_expected_sti_entities.json', expected_sti_entities)}#{write_file_shell('rails_mmd_expected_inheritances.json', expected_inheritances)}#{write_file_shell('rails_mmd_expected_sti_runtime.json', expected_runtime)}#{write_file_shell('rails_mmd_expected_delegated_type_runtime.json', expected_delegated_runtime)}#{write_file_shell('rails_mmd_expected_composite_runtime.json', expected_composite_runtime)}#{write_file_shell('rails_mmd_expected_specialized_options_runtime.json', expected_specialized_options_runtime)}#{write_file_shell('rails_mmd_expected_cross_domain_runtime.json', expected_cross_domain_runtime)}#{write_file_shell('rails_mmd_expected_core_er.mmd', expected_er_mermaid)}#{write_file_shell('rails_mmd_expected_core_class.mmd', expected_class_mermaid)}          mkdir -p tmp/rails_mmd
          cp "$RAILS_MMD_TEST_ROOT/#{actual_er_plan_fixture}" tmp/rails_mmd/core.er.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/#{actual_class_plan_fixture}" tmp/rails_mmd/core.class.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/#{expected_er_plan_fixture}" rails_mmd_expected_core_er.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/#{expected_class_plan_fixture}" rails_mmd_expected_core_class.render_plan.json
#{copy_fixture_shell('tmp/rails_mmd/core.diagnostics.json', actual_diagnostics_fixture)}
#{write_file_shell('tmp/rails_mmd/core.er.mmd', actual_er_mermaid)}#{write_file_shell('tmp/rails_mmd/core.class.mmd', actual_class_mermaid)}          #{'touch tmp/rails_mmd/secondary.er.mmd' if success_extra_artifact}
          exit 0 ;;
        *) exit 0 ;;
      esac
    SH
  end

  def write_file_shell(path, contents)
    return "rm -f #{path}\n" if contents.nil?

    body = contents.end_with?("\n") ? contents.delete_suffix("\n") : contents

    <<~SH
cat <<'EOF' > #{path}
#{body}
EOF
    SH
  end

  def copy_fixture_shell(path, fixture)
    return '' unless fixture

    %(cp "$RAILS_MMD_TEST_ROOT/#{fixture}" #{path}\n)
  end

  def fake_er_mermaid
    <<~MMD
      erDiagram
        direction LR
        %% sanitized comment
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

  def fake_class_mermaid
    <<~MMD
      classDiagram
        direction BT
        class ORDER
        class ACCOUNT
        ORDER "0..1" --> "0..*" ACCOUNT : billing_account
    MMD
  end

  def fake_class_sti_mermaid
    <<~MMD
      classDiagram
        direction BT
        class ADMIN_CAR_H111111111111
        class ADMIN_CAR_H222222222222["Admin::Car"]
        ADMIN_CAR_H111111111111 <|-- ADMIN_CAR_H222222222222
    MMD
  end

  def fake_sti_entities
    [
      {
        'entity_id' => 'entities/admin_cars/sti/Admin::Car',
        'entity_kind' => 'sti_subtype',
        'label' => 'Admin::Car',
        'safe_token' => 'ADMIN_CAR_H222222222222'
      }
    ]
  end

  def fake_sti_inheritances
    [
      {
        'inheritance_id' => 'inheritances/entities/admin_cars/sti/Admin::Car',
        'parent_entity_id' => 'entities/admin_cars',
        'child_entity_id' => 'entities/admin_cars/sti/Admin::Car',
        'parent_safe_token' => 'ADMIN_CAR_H111111111111',
        'child_safe_token' => 'ADMIN_CAR_H222222222222'
      }
    ]
  end

  def fake_sti_runtime
    [
      {
        'ruby_constant' => 'AdminCar',
        'base_class' => 'AdminCar',
        'table_name' => 'admin_cars',
        'inheritance_column' => 'type',
        'sti_name' => 'AdminCar',
        'abstract_class' => false,
        'descends_from_active_record' => true
      },
      {
        'ruby_constant' => 'Admin::Car',
        'base_class' => 'AdminCar',
        'table_name' => 'admin_cars',
        'inheritance_column' => 'type',
        'sti_name' => 'Car',
        'abstract_class' => false,
        'descends_from_active_record' => false
      }
    ]
  end

  def run_matrix(path: ENV.fetch('PATH'), pair: nil, fixture_family: nil)
    env = { 'PATH' => path, 'RAILS_MMD_MATRIX_PAIR' => pair, 'RAILS_MMD_TEST_ROOT' => Dir.pwd }
    env['RAILS_MMD_MATRIX_FIXTURE_FAMILY'] = fixture_family if fixture_family

    stdout, stderr, status = Open3.capture3(env, 'bundle', 'exec', 'rake', 'verify:rails_matrix')
    { success: status.success?, stdout: stdout, stderr: stderr, output: stdout + stderr }
  end

  def rake_prerequisites
    stdout, = Open3.capture3('bundle', 'exec', 'rake', '--prereqs')
    stdout
  end

  def with_fake_asdf(script)
    Dir.mktmpdir('rails-matrix-bin') do |bin_dir|
      asdf = File.join(bin_dir, 'asdf')
      File.write(asdf, "#!/bin/sh\n#{script}\n")
      FileUtils.chmod('+x', asdf)
      yield "#{bin_dir}:#{ENV.fetch('PATH')}"
    end
  end

  it 'reports how to install a missing matrix Ruby version' do
    with_fake_asdf('exit 1') do |path|
      expect(run_matrix(path: path)).to include(success: false, output: include('asdf install ruby 4.0.6'))
    end
  end

  it 'reports how to install the required Bundler version for a matrix Ruby' do
    with_fake_asdf('[ "$1" = "where" ] && exit 0; exit 1') do |path|
      expect(run_matrix(path: path)).to include(success: false, output: include('gem install bundler -v 4.0.10'))
    end
  end

  it 'checks prerequisites only for the selected diagnostic pair' do
    with_fake_asdf(selected_pair_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result[:output]).not_to include('Missing matrix Ruby 3.3.12')
    end
  end

  it 'runs every configured fixture family for a selected matrix pair' do
    with_fake_asdf(matching_fake_app_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(
        success: true,
        output: include(
          'PASS ruby-4.0.6-rails-8.1 [default]',
          'PASS ruby-4.0.6-rails-8.1 [delegated_type]',
          'PASS ruby-4.0.6-rails-8.1 [composite_keys]'
        )
      )
    end
  end

  it 'runs the composite-key family and Rails 7.2 runtime probe branch' do
    with_fake_asdf(matching_rails72_fake_app_asdf) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-7.2', fixture_family: 'composite_keys'
      )

      expect(result).to include(
        success: true,
        output: include('PASS ruby-4.0.6-rails-7.2 [composite_keys]')
      )
    end
  end

  it 'runs the cross-domain multi-DB success and collision scenarios' do
    with_fake_asdf(matching_fake_app_asdf) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: true,
        output: include('PASS ruby-4.0.6-rails-8.1 [cross_domain_multi_db]')
      )
    end
  end

  it 'rejects cross-domain success publication beyond its closed artifact set' do
    with_fake_asdf(fake_generated_app_asdf(success_extra_artifact: true)) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: false,
        output: include('success publication did not match expectation')
      )
    end
  end

  it 'rejects a mismatched cross-domain entity oracle' do
    with_fake_asdf(fake_generated_app_asdf(expected_entities: '[]')) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(success: false, output: include('entities did not match expectation'))
    end
  end

  it 'rejects a mismatched cross-domain runtime oracle' do
    with_fake_asdf(fake_generated_app_asdf(expected_cross_domain_runtime: '[{"unexpected":true}]')) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: false,
        output: include('cross-domain multi-DB runtime did not match expectation')
      )
    end
  end

  it 'rejects mismatched exact collision diagnostics' do
    with_fake_asdf(fake_generated_app_asdf(collision_expectation_mismatch: true)) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(success: false, output: include('collision diagnostics did not match expectation'))
    end
  end

  it 'rejects unknown connection-boundary probe evidence' do
    payload = connection_boundary_probe_payload.merge('unexpected' => true)

    with_fake_asdf(fake_generated_app_asdf(connection_boundary_probe: payload)) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: false,
        output: include('connection boundary probe did not match expectation')
      )
    end
  end

  it 'rejects collision publication beyond the diagnostics artifact' do
    with_fake_asdf(fake_generated_app_asdf(collision_extra_artifact: true)) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: false,
        output: include('collision publication did not match expectation')
      )
    end
  end

  it 'rejects unredacted collision connection material' do
    with_fake_asdf(fake_generated_app_asdf(collision_leak: true)) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'cross_domain_multi_db'
      )

      expect(result).to include(
        success: false,
        output: include('collision diagnostics leaked forbidden connection material')
      )
    end
  end

  it 'rejects a missing composite-key runtime expectation' do
    with_fake_asdf(missing_expected_composite_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'composite_keys')

      expect(result).to include(
        success: false,
        output: include('missing or invalid expected rails_mmd_expected_composite_runtime.json')
      )
    end
  end

  it 'rejects malformed composite-key runtime output' do
    with_fake_asdf(malformed_composite_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'composite_keys')

      expect(result).to include(success: false, output: include('published invalid composite_runtime.json'))
    end
  end

  it 'rejects mismatched composite-key runtime output' do
    with_fake_asdf(mismatched_expected_composite_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'composite_keys')

      expect(result).to include(success: false, output: include('composite key runtime did not match expectation'))
    end
  end

  it 'rejects a composite HABTM probe that loses the conventional scalar fallback' do
    with_fake_asdf(failing_composite_habtm_probe_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'composite_keys')

      expect(result).to include(success: false, output: include('composite HABTM probe did not match expectation'))
    end
  end

  it 'rejects a composite render plan that differs from its checked-in exact oracle' do
    asdf = fake_generated_app_asdf(expected_er_plan_fixture: 'fixtures/schemas/render_plan/valid/class.json')

    with_fake_asdf(asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'composite_keys')

      expect(result).to include(success: false, output: include('ER render plan did not match expectation'))
    end
  end

  it 'projects every composite polymorphic identifier member and the scalar type member' do
    tuple_payload = 'WyJzdWJqZWN0X3Nob3BfaWQiLCJzdWJqZWN0X2lkIl0'
    relationship_id =
      "relationships/composite_comments/polymorphic/commentable/tuple/#{tuple_payload}/commentable_type/posts"
    render_plan = {
      'entities' => [
        {
          'safe_token' => 'COMPOSITE_COMMENT',
          'attributes' => [
            { 'label' => 'subject_shop_id', 'key_marker' => 'PK, FK' },
            { 'label' => 'subject_id', 'key_marker' => 'FK' },
            { 'label' => 'commentable_type', 'key_marker' => 'FK' }
          ]
        }
      ],
      'relationships' => [
        {
          'relationship_id' => relationship_id,
          'owner_safe_token' => 'COMPOSITE_COMMENT',
          'target_safe_token' => 'POST',
          'label' => 'commentable'
        }
      ]
    }

    expect(RailsMatrix::PolymorphicGroupProjector.call(render_plan)).to eq(
      [
        {
          'group_id' => relationship_id.split('/')[0...-1].join('/'),
          'holder_safe_token' => 'COMPOSITE_COMMENT',
          'root_label' => 'commentable',
          'candidate_target_safe_tokens' => ['POST'],
          'foreign_key_attributes' => %w[commentable_type subject_id subject_shop_id]
        }
      ]
    )
  end

  it 'rejects malformed composite polymorphic group tuple payloads' do
    render_plan = {
      'entities' => [{ 'safe_token' => 'COMMENT', 'attributes' => [] }],
      'relationships' => [
        {
          'relationship_id' =>
            'relationships/comments/polymorphic/commentable/tuple/not-base64/commentable_type/posts',
          'owner_safe_token' => 'COMMENT',
          'target_safe_token' => 'POST',
          'label' => 'commentable'
        }
      ]
    }

    expect { RailsMatrix::PolymorphicGroupProjector.call(render_plan) }
      .to raise_error(RailsMatrix::VerificationError, /malformed polymorphic relationship ID/)
  end

  it 'passes delegated-type fixture-family selection through to the runner' do
    with_fake_asdf(invalid_artifact_asdf) do |path|
      result = run_matrix(
        path: path,
        pair: 'ruby-4.0.6-rails-8.1',
        fixture_family: 'delegated_type'
      )

      expect(result).to include(success: false, output: include('schema-invalid core.er.render_plan.json'))
    end
  end

  it 'does not leak the fixture selector into the real Rails application' do
    isolated_asdf = <<~SH
      [ "$1" = "where" ] && exit 0
      case "$*" in *--version*) exit 0 ;; esac
      [ -n "$RAILS_MMD_MATRIX_FIXTURE_FAMILY" ] && exit 9
      #{matching_fake_app_asdf}
    SH

    with_fake_asdf(isolated_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'delegated_type')

      expect(result).to include(success: true)
    end
  end

  it 'reuses the same mismatch assertions for delegated-type fixture-family oracles' do
    with_fake_asdf(missing_expected_relationships_asdf) do |path|
      result = run_matrix(
        path: path,
        pair: 'ruby-4.0.6-rails-8.1',
        fixture_family: 'delegated_type'
      )

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'rejects a missing delegated-type runtime expectation' do
    with_fake_asdf(missing_expected_delegated_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'delegated_type')

      expect(result).to include(
        success: false,
        output: include('missing or invalid expected rails_mmd_expected_delegated_type_runtime.json')
      )
    end
  end

  it 'rejects malformed delegated-type runtime output' do
    with_fake_asdf(malformed_delegated_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'delegated_type')

      expect(result).to include(success: false, output: include('published invalid delegated_type_runtime.json'))
    end
  end

  it 'rejects mismatched delegated-type runtime output' do
    with_fake_asdf(mismatched_expected_delegated_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'delegated_type')

      expect(result).to include(success: false, output: include('delegated type runtime did not match expectation'))
    end
  end

  it 'passes specialized-options fixture-family selection through to the runner' do
    with_fake_asdf(invalid_artifact_asdf) do |path|
      result = run_matrix(
        path: path,
        pair: 'ruby-4.0.6-rails-8.1',
        fixture_family: 'specialized_options'
      )

      expect(result).to include(success: false, output: include('schema-invalid core.er.render_plan.json'))
    end
  end

  it 'rejects a missing specialized-options runtime expectation' do
    with_fake_asdf(missing_expected_specialized_options_runtime_asdf) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'specialized_options'
      )

      expect(result).to include(
        success: false,
        output: include('missing or invalid expected rails_mmd_expected_specialized_options_runtime.json')
      )
    end
  end

  it 'rejects mismatched specialized-options runtime output' do
    with_fake_asdf(mismatched_expected_specialized_options_runtime_asdf) do |path|
      result = run_matrix(
        path: path, pair: 'ruby-4.0.6-rails-8.1', fixture_family: 'specialized_options'
      )

      expect(result).to include(
        success: false,
        output: include('specialized options runtime did not match expectation')
      )
    end
  end

  it 'rejects an unknown delegated-type fixture family name' do
    with_fake_asdf('exit 0') do |path|
      result = run_matrix(
        path: path,
        pair: 'ruby-4.0.6-rails-8.1',
        fixture_family: 'does_not_exist'
      )

      expect(result).to include(success: false, output: include('Unknown rails matrix fixture family: does_not_exist'))
    end
  end

  it 'rejects parseable render plans that violate the public artifact schema' do
    with_fake_asdf(invalid_artifact_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('schema-invalid core.er.render_plan.json'))
    end
  end

  it 'rejects Mermaid that does not match its validated render plan' do
    with_fake_asdf(malformed_mermaid_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('does not match core.er.render_plan.json'))
    end
  end

  it 'rejects generated diagnostics that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_diagnostics_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('diagnostics did not match expectation'))
    end
  end

  it 'rejects unexpected generated diagnostics when the exact expectation is empty' do
    with_fake_asdf(unexpected_diagnostics_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('diagnostics did not match expectation'))
    end
  end

  it 'rejects generated relationships that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_relationships_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'rejects an expected relationship whose scoped metadata was removed' do
    with_fake_asdf(changed_expected_scoped_metadata_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'rejects generated polymorphic groups that do not match the real-app expectation' do
    with_fake_asdf(missing_expected_polymorphic_groups_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('polymorphic groups did not match expectation'))
    end
  end

  it 'rejects artifacts whose only missing expected relationship is HABTM' do
    with_fake_asdf(missing_expected_habtm_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('relationships did not match expectation'))
    end
  end

  it 'rejects a matrix app with no checked-in class Mermaid oracle' do
    with_fake_asdf(missing_expected_class_oracle_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('expected_core_class.mmd'))
    end
  end

  it 'rejects a matrix app with no checked-in ER Mermaid oracle' do
    with_fake_asdf(missing_expected_er_oracle_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('expected_core_er.mmd'))
    end
  end

  it 'rejects a matrix app with no checked-in STI JSON oracle' do
    with_fake_asdf(missing_expected_sti_entities_oracle_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('invalid expected rails_mmd_expected_sti_entities'))
    end
  end

  it 'rejects a class Mermaid artifact that differs from its checked-in oracle' do
    with_fake_asdf(mismatched_expected_class_oracle_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('class Mermaid did not match expectation'))
    end
  end

  it 'rejects an ER Mermaid artifact that differs from its checked-in oracle' do
    with_fake_asdf(mismatched_expected_er_oracle_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('ER Mermaid did not match expectation'))
    end
  end

  it 'rejects STI subtype node projections that differ from the checked-in class oracle' do
    with_fake_asdf(mismatched_expected_sti_entities_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('STI entities did not match expectation'))
    end
  end

  it 'rejects STI inheritance projections that differ from the checked-in class oracle' do
    with_fake_asdf(mismatched_expected_inheritances_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('inheritances did not match expectation'))
    end
  end

  it 'rejects STI runtime projections that differ from the checked-in Rails oracle' do
    with_fake_asdf(mismatched_expected_sti_runtime_asdf) do |path|
      result = run_matrix(path: path, pair: 'ruby-4.0.6-rails-8.1')

      expect(result).to include(success: false, output: include('STI runtime did not match expectation'))
    end
  end

  it 'executes every required Ruby and Rails pair' do
    expect(run_matrix).to include(success: true, stderr: '', stdout: include('PASS 3/3 Rails matrix pairs'))
  end

  it 'runs the Rails matrix from the default local verification gate' do
    expect(rake_prerequisites).to match(/rake default\n(?: {4}.+\n)* {4}verify:rails_matrix/)
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Layout/HeredocIndentation
