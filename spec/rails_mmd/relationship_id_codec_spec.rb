# frozen_string_literal: true

require 'rails_mmd/relationship_id_codec'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::RelationshipIdCodec do
  describe '.key_segments' do
    it 'keeps punctuation-heavy composite tuples collision-free without reserving scalar tuple' do
      first = described_class.key_segments(['tenant,id', 'tuple/looks_like_marker'])
      second = described_class.key_segments(['tenant', 'id,tuple/looks_like_marker'])

      expect(first).to eq(%w[tuple WyJ0ZW5hbnQsaWQiLCJ0dXBsZS9sb29rc19saWtlX21hcmtlciJd])
      expect(second).not_to eq(first)
      expect(described_class.key_segments(['tuple'])).to eq(['tuple'])
    end
  end

  describe '.direct' do
    it 'preserves the existing scalar relationship ID byte for byte' do
      expect(
        described_class.direct(
          holder_table: 'users',
          foreign_key_columns: ['account_id'],
          referenced_table: 'accounts',
          referenced_key_columns: ['id']
        )
      ).to eq('relationships/users/account_id/accounts/id')
    end

    it 'encodes each composite tuple as a marker and canonical base64url payload' do
      expect(
        described_class.direct(
          holder_table: 'basket_items',
          foreign_key_columns: %w[shop_id basket_id],
          referenced_table: 'baskets',
          referenced_key_columns: %w[shop_id id]
        )
      ).to eq(
        'relationships/basket_items/tuple/WyJzaG9wX2lkIiwiYmFza2V0X2lkIl0/' \
        'baskets/tuple/WyJzaG9wX2lkIiwiaWQiXQ'
      )
    end

    it 'rejects unequal direct key tuples before emitting an invalid grammar' do
      expect do
        described_class.direct(
          holder_table: 'items', foreign_key_columns: %w[tenant_id target_id],
          referenced_table: 'targets', referenced_key_columns: ['id']
        )
      end.to raise_error(described_class::Error)
    end
  end

  describe '.decode_direct' do
    it 'decodes by full grammar so a scalar column named tuple remains scalar' do
      composite_id = described_class.direct(
        holder_table: 'basket_items',
        foreign_key_columns: %w[shop_id basket_id],
        referenced_table: 'baskets',
        referenced_key_columns: %w[shop_id id]
      )

      expect(described_class.decode_direct(composite_id)).to eq(
        holder_table: 'basket_items',
        foreign_key_columns: %w[shop_id basket_id],
        referenced_table: 'baskets',
        referenced_key_columns: %w[shop_id id]
      )
      expect(described_class.decode_direct('relationships/events/tuple/categories/tuple')).to eq(
        holder_table: 'events',
        foreign_key_columns: ['tuple'],
        referenced_table: 'categories',
        referenced_key_columns: ['tuple']
      )
    end

    it 'raises a codec error for malformed markers and payloads without scalar fallback' do
      malformed_ids = [
        'other/items/account_id/accounts/id',
        'relationships/items/too/short',
        'relationships/items/not-tuple/WyJhIiwiYiJd/targets/tuple/WyJhIiwiYiJd',
        'relationships/items/tuple/not+base64/targets/tuple/WyJhIiwiYiJd',
        'relationships/items/tuple/WyJpZCJd/targets/tuple/WyJhIiwiYiJd',
        'relationships/items/tuple/WyJpZCIsImlkIl0/targets/tuple/WyJhIiwiYiJd',
        'relationships/items/tuple/WyJhIiwiYiIsImMiXQ/targets/tuple/WyJhIiwiYiJd',
        'relationships/items/tuple/WyAiYSIsImIiXQ/targets/tuple/WyJhIiwiYiJd'
      ]

      malformed_ids.each do |id|
        expect { described_class.decode_direct(id) }.to raise_error(described_class::Error)
      end
    end
  end

  describe 'polymorphic IDs' do
    it 'preserves scalar IDs and round trips composite relationship and group grammars' do
      scalar_id = described_class.polymorphic(
        holder_table: 'comments', interface: 'commentable', identifier_columns: ['commentable_id'],
        type_column: 'commentable_type', target_table: 'posts'
      )
      composite_id = described_class.polymorphic(
        holder_table: 'comments', interface: 'commentable', identifier_columns: %w[tenant_id commentable_id],
        type_column: 'commentable_type', target_table: 'posts'
      )
      group_id = described_class.polymorphic_group(
        holder_table: 'comments', interface: 'commentable', identifier_columns: %w[tenant_id commentable_id],
        type_column: 'commentable_type'
      )

      expect(scalar_id).to eq(
        'relationships/comments/polymorphic/commentable/commentable_id/commentable_type/posts'
      )
      expect(described_class.decode_polymorphic(scalar_id)).to eq(
        holder_table: 'comments', interface: 'commentable', identifier_columns: ['commentable_id'],
        type_column: 'commentable_type', target_table: 'posts'
      )
      expect(described_class.decode_polymorphic(composite_id)).to eq(
        holder_table: 'comments', interface: 'commentable', identifier_columns: %w[tenant_id commentable_id],
        type_column: 'commentable_type', target_table: 'posts'
      )
      expect(described_class.decode_polymorphic_group(group_id)).to eq(
        holder_table: 'comments', interface: 'commentable', identifier_columns: %w[tenant_id commentable_id],
        type_column: 'commentable_type'
      )
      expect(
        described_class.decode_polymorphic_group('relationships/events/polymorphic/subject/tuple/subject_type')
      ).to eq(
        holder_table: 'events', interface: 'subject', identifier_columns: ['tuple'], type_column: 'subject_type'
      )
    end

    it 'rejects malformed composite group marker and payload forms' do
      malformed_ids = [
        'relationships/events/polymorphic/subject/not-tuple/WyJhIiwiYiJd/subject_type',
        'relationships/events/polymorphic/subject/tuple/WyJpZCJd/subject_type'
      ]

      malformed_ids.each do |id|
        expect { described_class.decode_polymorphic_group(id) }.to raise_error(described_class::Error)
      end
    end

    it 'rejects malformed scalar and composite relationship key productions' do
      malformed_ids = [
        'relationships/events/polymorphic/subject//subject_type/posts',
        'relationships/events/polymorphic/subject/not-tuple/WyJhIiwiYiJd/subject_type/posts',
        'relationships/events/polymorphic/subject/tuple/not+base64/subject_type/posts'
      ]

      malformed_ids.each do |id|
        expect { described_class.decode_polymorphic(id) }.to raise_error(described_class::Error)
      end
      expect do
        described_class.decode_polymorphic_group(
          'relationships/events/polymorphic/subject//subject_type'
        )
      end.to raise_error(described_class::Error)
    end

    it 'rejects IDs outside the complete relationship and group grammars' do
      malformed_relationship_ids = [
        'other/events/polymorphic/subject/subject_id/subject_type/posts',
        'relationships/events/polymorphic/subject/subject_id'
      ]
      malformed_group_ids = [
        'other/events/polymorphic/subject/subject_id/subject_type',
        'relationships/events/polymorphic/subject/subject_id'
      ]

      malformed_relationship_ids.each do |id|
        expect { described_class.decode_polymorphic(id) }.to raise_error(described_class::Error)
      end
      malformed_group_ids.each do |id|
        expect { described_class.decode_polymorphic_group(id) }.to raise_error(described_class::Error)
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
