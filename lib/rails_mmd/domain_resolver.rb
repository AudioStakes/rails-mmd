# frozen_string_literal: true

require 'rails_mmd/diagnostics'

module RailsMmd
  # Resolves configured domains exactly against schema-free inventory records.
  class DomainResolver
    DomainResult = Struct.new(:domain_id, :records, :diagnostics, keyword_init: true)
    Result = Struct.new(:domains, :diagnostics, keyword_init: true)

    def initialize(diagnostics: Diagnostics.new)
      @diagnostics = diagnostics
    end

    def resolve(config:, inventory_records:)
      records_by_constant = inventory_records.to_h { |record| [record.ruby_constant, record] }
      domain_results = config.selected_domain_ids.map do |domain_id|
        resolve_domain(config.domains.fetch(domain_id), records_by_constant)
      end
      all_diagnostics = domain_results.flat_map(&:diagnostics)

      Result.new(domains: domain_results, diagnostics: all_diagnostics)
    end

    private

    attr_reader :diagnostics

    def resolve_domain(domain, records_by_constant)
      include_records, include_diagnostics = resolve_model_list(domain, domain.include_models, records_by_constant)
      exclude_records, exclude_diagnostics = resolve_model_list(domain, domain.exclude_models, records_by_constant)
      selected_records = selected_records(include_records, exclude_records)
      empty_diagnostic = selected_records.empty? ? [domain_empty(domain.id)] : []

      DomainResult.new(
        domain_id: domain.id,
        records: selected_records,
        diagnostics: include_diagnostics + exclude_diagnostics + empty_diagnostic
      )
    end

    def selected_records(include_records, exclude_records)
      excluded = exclude_records.to_set(&:ruby_constant)
      seen = Set.new
      include_records.each_with_object([]) do |record, selected|
        next if excluded.include?(record.ruby_constant) || seen.include?(record.ruby_constant)

        seen << record.ruby_constant
        selected << record
      end
    end

    def resolve_model_list(domain, ruby_constants, records_by_constant)
      ruby_constants.each_with_object([[], []]) do |ruby_constant, (records, output_diagnostics)|
        record = records_by_constant[ruby_constant]
        if record.nil?
          output_diagnostics << model_not_found(domain.id, ruby_constant)
        elsif record.renderable
          records << record
        else
          output_diagnostics << model_not_renderable(domain.id, record)
        end
      end
    end

    def model_not_found(domain_id, ruby_constant)
      diagnostics.build(
        code: 'DOMAIN_MODEL_NOT_FOUND',
        message: "Domain #{domain_id} references missing model #{ruby_constant}",
        subject_id: "#{domain_id}:#{ruby_constant}",
        metadata: { domain_id: domain_id, ruby_constant: ruby_constant }
      )
    end

    def model_not_renderable(domain_id, record)
      diagnostics.build(
        code: 'DOMAIN_MODEL_NOT_RENDERABLE',
        message: "Domain #{domain_id} references non-renderable model #{record.ruby_constant}",
        subject_id: "#{domain_id}:#{record.ruby_constant}",
        metadata: {
          domain_id: domain_id,
          ruby_constant: record.ruby_constant,
          renderability_reason: record.renderability_reason
        }
      )
    end

    def domain_empty(domain_id)
      diagnostics.build(
        code: 'DOMAIN_EMPTY',
        message: "Domain #{domain_id} has no renderable models",
        subject_id: domain_id,
        metadata: { domain_id: domain_id }
      )
    end
  end
end
