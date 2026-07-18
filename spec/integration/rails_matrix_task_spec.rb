# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# rubocop:disable Metrics/MethodLength, Metrics/ParameterLists, Layout/HeredocIndentation
RSpec.describe 'the Rails compatibility matrix Rake command' do
  let(:matching_fake_app_asdf) { fake_generated_app_asdf }

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

  def generic_expected_relationship
    {
      relationship_id: 'relationships/users/account', owner_safe_token: 'USER', target_safe_token: 'ACCOUNT',
      label: 'account', owner_cardinality: '0..many', target_cardinality: '1..1', metadata: { scoped: true }
    }
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
    actual_er_mermaid: fake_er_mermaid,
    actual_class_mermaid: fake_class_mermaid,
    expected_er_mermaid: fake_er_mermaid,
    expected_class_mermaid: fake_class_mermaid,
    expected_diagnostics: '[]',
    expected_relationships: JSON.pretty_generate([generic_expected_relationship]),
    expected_polymorphic_groups: '[]',
    expected_sti_entities: '[]',
    expected_inheritances: '[]',
    expected_runtime: '[]',
    actual_runtime: '[]',
    expected_delegated_runtime: '[]',
    actual_delegated_runtime: '[]',
    actual_diagnostics_fixture: nil
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
        *"exec rails-mmd generate"*)
#{write_file_shell('rails_mmd_expected_diagnostics.json', expected_diagnostics)}#{write_file_shell('rails_mmd_expected_relationships.json', expected_relationships)}#{write_file_shell('rails_mmd_expected_polymorphic_groups.json', expected_polymorphic_groups)}#{write_file_shell('rails_mmd_expected_sti_entities.json', expected_sti_entities)}#{write_file_shell('rails_mmd_expected_inheritances.json', expected_inheritances)}#{write_file_shell('rails_mmd_expected_sti_runtime.json', expected_runtime)}#{write_file_shell('rails_mmd_expected_delegated_type_runtime.json', expected_delegated_runtime)}#{write_file_shell('rails_mmd_expected_core_er.mmd', expected_er_mermaid)}#{write_file_shell('rails_mmd_expected_core_class.mmd', expected_class_mermaid)}          mkdir -p tmp/rails_mmd
          cp "$RAILS_MMD_TEST_ROOT/#{actual_er_plan_fixture}" tmp/rails_mmd/core.er.render_plan.json
          cp "$RAILS_MMD_TEST_ROOT/#{actual_class_plan_fixture}" tmp/rails_mmd/core.class.render_plan.json
#{copy_fixture_shell('tmp/rails_mmd/core.diagnostics.json', actual_diagnostics_fixture)}
#{write_file_shell('tmp/rails_mmd/core.er.mmd', actual_er_mermaid)}#{write_file_shell('tmp/rails_mmd/core.class.mmd', actual_class_mermaid)}          exit 0 ;;
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
          'PASS ruby-4.0.6-rails-8.1 [delegated_type]'
        )
      )
    end
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
# rubocop:enable Metrics/MethodLength, Metrics/ParameterLists, Layout/HeredocIndentation
