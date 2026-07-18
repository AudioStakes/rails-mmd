# frozen_string_literal: true

require 'base64'
require 'json'

require_relative 'key_tuple'

module RailsMmd
  # Full-grammar decoders kept separate from relationship-ID encoding.
  module RelationshipIdDecoding
    def decode_direct(id)
      segments = id.to_s.split('/', -1)
      raise RelationshipIdCodec::Error, 'malformed direct relationship ID' unless segments.first == 'relationships'
      return decode_direct_scalar(segments) if segments.length == 5
      return decode_direct_composite(segments) if segments.length == 7

      raise RelationshipIdCodec::Error, 'malformed direct relationship ID'
    end

    def decode_polymorphic(id)
      segments = polymorphic_segments(id)
      return decode_polymorphic_scalar(segments) if segments.length == 7
      return decode_polymorphic_composite(segments) if segments.length == 8

      raise RelationshipIdCodec::Error, 'malformed polymorphic relationship ID'
    end

    def decode_polymorphic_group(id)
      segments = polymorphic_segments(id)

      case segments.length
      when 6
        polymorphic_parts(segments[1], segments[3], [segments[4]], segments[5])
      when 7
        raise RelationshipIdCodec::Error, 'malformed polymorphic group tuple marker' unless segments[4] == 'tuple'

        polymorphic_parts(segments[1], segments[3], decode_tuple_payload(segments[5]), segments[6])
      else
        raise RelationshipIdCodec::Error, 'malformed polymorphic group ID'
      end
    end

    private

    def decode_direct_scalar(segments)
      direct_parts(segments[1], [segments[2]], segments[3], [segments[4]])
    end

    def decode_direct_composite(segments)
      markers_valid = segments[2] == 'tuple' && segments[5] == 'tuple'
      raise RelationshipIdCodec::Error, 'malformed direct relationship tuple marker' unless markers_valid

      direct_parts(segments[1], decode_tuple_payload(segments[3]), segments[4], decode_tuple_payload(segments[6]))
    end

    def decode_polymorphic_scalar(segments)
      polymorphic_parts(segments[1], segments[3], [segments[4]], segments[5], target_table: segments[6])
    end

    def decode_polymorphic_composite(segments)
      raise RelationshipIdCodec::Error, 'malformed polymorphic relationship tuple marker' unless segments[4] == 'tuple'

      polymorphic_parts(
        segments[1], segments[3], decode_tuple_payload(segments[5]), segments[6], target_table: segments[7]
      )
    end

    def direct_parts(holder_table, foreign_key_columns, referenced_table, referenced_key_columns)
      unless KeyTuple.valid_pair?(foreign_key_columns, referenced_key_columns)
        raise RelationshipIdCodec::Error, 'direct relationship key tuple pair is invalid'
      end

      {
        holder_table: holder_table,
        foreign_key_columns: foreign_key_columns,
        referenced_table: referenced_table,
        referenced_key_columns: referenced_key_columns
      }
    end

    def polymorphic_segments(id)
      segments = id.to_s.split('/', -1)
      return segments if segments[0] == 'relationships' && segments[2] == 'polymorphic'

      raise RelationshipIdCodec::Error, 'malformed polymorphic relationship ID'
    end

    def polymorphic_parts(holder_table, interface, identifier_columns, type_column, target_table: nil)
      parts = { holder_table: holder_table, interface: interface, identifier_columns: identifier_columns,
                type_column: type_column }
      parts[:target_table] = target_table if target_table
      parts
    end

    def decode_tuple_payload(payload)
      payload_valid = payload.match?(/\A[A-Za-z0-9_-]+\z/)
      raise RelationshipIdCodec::Error, 'malformed relationship tuple payload' unless payload_valid

      decoded = JSON.parse(Base64.urlsafe_decode64(payload))
      tuple = KeyTuple.normalize(decoded)
      raise RelationshipIdCodec::Error, 'malformed relationship tuple payload' unless tuple&.length.to_i >= 2

      encoded = Base64.urlsafe_encode64(KeyTuple.identity(tuple), padding: false)
      raise RelationshipIdCodec::Error, 'non-canonical relationship tuple payload' unless encoded == payload

      tuple
    rescue JSON::ParserError, ArgumentError
      raise RelationshipIdCodec::Error, 'malformed relationship tuple payload'
    end
  end

  # Encodes and decodes scalar-stable relationship identifiers.
  module RelationshipIdCodec
    extend RelationshipIdDecoding

    class Error < ArgumentError; end

    module_function

    def direct(holder_table:, foreign_key_columns:, referenced_table:, referenced_key_columns:)
      raise Error, 'direct relationship key tuple pair is invalid' unless KeyTuple.valid_pair?(
        foreign_key_columns, referenced_key_columns
      )

      foreign_segments = key_segments(foreign_key_columns)
      referenced_segments = key_segments(referenced_key_columns)
      ['relationships', holder_table, *foreign_segments, referenced_table, *referenced_segments].join('/')
    end

    def polymorphic(holder_table:, interface:, identifier_columns:, type_column:, target_table:)
      segments = [
        'relationships', holder_table, 'polymorphic', interface, *key_segments(identifier_columns), type_column,
        target_table
      ]
      segments.join('/')
    end

    def polymorphic_group(holder_table:, interface:, identifier_columns:, type_column:)
      segments = [
        'relationships', holder_table, 'polymorphic', interface, *key_segments(identifier_columns), type_column
      ]
      segments.join('/')
    end

    def key_segments(tuple)
      normalized = KeyTuple.normalize(tuple)
      raise Error, 'relationship key tuple is invalid' unless normalized
      return normalized if normalized.one?

      ['tuple', Base64.urlsafe_encode64(KeyTuple.identity(normalized), padding: false)]
    end
  end

  private_constant :RelationshipIdDecoding
end
