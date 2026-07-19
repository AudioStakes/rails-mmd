# frozen_string_literal: true

require 'rails_mmd/diagnostics'

module RailsMmd
  # Resolves configured domains exactly against schema-free inventory records.
  class DomainResolver
    DomainResult = Struct.new(:domain_id, :records, :diagnostics, :excluded_ruby_constants, keyword_init: true)
    Result = Struct.new(:domains, :diagnostics, :exit_code, :owned_domain_ids_by_constant, keyword_init: true) do
      def success? = diagnostics.empty?
    end

    EXIT_CONTRACT_ERROR = 2

    def initialize(diagnostics: Diagnostics.new)
      @diagnostics = diagnostics
    end

    def resolve(config:, inventory_records:)
      records_by_constant = inventory_records.to_h { |record| [record.ruby_constant, record] }
      domain_results = config.selected_domain_ids.map do |domain_id|
        resolve_domain(config.domains.fetch(domain_id), records_by_constant)
      end
      all_diagnostics = domain_results.flat_map(&:diagnostics)
      owned_domain_ids_by_constant = build_owned_domain_ids_by_constant(config)
      Result.new(domains: domain_results, diagnostics: all_diagnostics,
                 exit_code: all_diagnostics.empty? ? 0 : EXIT_CONTRACT_ERROR,
                 owned_domain_ids_by_constant: owned_domain_ids_by_constant)
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
        diagnostics: include_diagnostics + exclude_diagnostics + empty_diagnostic,
        excluded_ruby_constants: domain.exclude_models.uniq.sort
      )
    end

    def build_owned_domain_ids_by_constant(config)
      ownership = ownership_groups(config)
      ownership.sort.to_h { |ruby_constant, domain_ids| [ruby_constant, domain_ids.uniq.sort] }
    end

    def included_constants(domain)
      excluded = domain.exclude_models.to_set
      domain.include_models.each_with_object([]) do |ruby_constant, included|
        included << ruby_constant unless excluded.include?(ruby_constant)
      end.uniq
    end

    def ownership_groups(config)
      config.domains.keys.sort.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |domain_id, output|
        append_owned_domain_ids(output, domain_id, config.domains.fetch(domain_id))
      end
    end

    def append_owned_domain_ids(output, domain_id, domain)
      included_constants(domain).each { |ruby_constant| output[ruby_constant] << domain_id }
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
