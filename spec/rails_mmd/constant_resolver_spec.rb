# frozen_string_literal: true

require 'rails_mmd/constant_resolver'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RailsMmd::ConstantResolver do
  it 'resolves nested constants without inheriting constants from ancestors' do
    namespace = Module.new
    model = Class.new
    inherited_model = Class.new
    base = Class.new
    base.const_set(:InheritedModel, inherited_model)
    child = Class.new(base)
    namespace.const_set(:Model, model)
    namespace.const_set(:Child, child)
    stub_const('ConstantResolverSpecNamespace', namespace)

    resolver = described_class.new

    expect(resolver.resolve('ConstantResolverSpecNamespace::Model')).to equal(model)
    expect(resolver.resolve('ConstantResolverSpecNamespace::Child::InheritedModel')).to be_nil
  end

  it 'adapts injected lookup callables and contains ordinary resolution failures' do
    model = Class.new
    resolver = described_class.wrap({ 'Model' => model }.method(:fetch))

    expect(resolver.resolve('Model')).to equal(model)
    expect(resolver.resolve('MissingModel')).to be_nil
  end

  it 'contains script and standard errors behind the resolution interface' do
    [LoadError, SyntaxError, NotImplementedError, RuntimeError].each do |error_class|
      resolver = described_class.new(loader: ->(_name) { raise error_class, 'autoload failed' })

      expect(resolver.resolve('BrokenModel')).to be_nil
    end
  end

  it 'does not contain process-control or resource exceptions' do
    [Interrupt, SystemExit, NoMemoryError].each do |error_class|
      resolver = described_class.new(loader: ->(_name) { raise error_class })

      expect { resolver.resolve('Model') }.to raise_error(error_class)
    end
  end

  it 'preserves an existing resolver when adapting dependencies' do
    resolver = described_class.new

    expect(described_class.wrap(resolver)).to equal(resolver)
  end

  it 'adapts resolver objects behind the contained interface' do
    model = Class.new
    adapter = Object.new
    adapter.define_singleton_method(:resolve) { |name| { 'Model' => model }.fetch(name) }

    resolver = described_class.wrap(adapter)

    expect(resolver.resolve('Model')).to equal(model)
    expect(resolver.resolve('MissingModel')).to be_nil
  end

  it 'fails fast when adapting objects that expose neither resolve nor call' do
    expect { described_class.wrap(Object.new) }
      .to raise_error(ArgumentError, 'constant resolver must respond to resolve or call')
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
