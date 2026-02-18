require 'rails_helper'

RSpec.describe Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer do
  subject(:normalizer) { described_class.new }

  describe '#handles_country?' do
    it 'returns true for Mexico numbers with country code 52' do
      expect(normalizer.handles_country?('5215512345678')).to be true
      expect(normalizer.handles_country?('525512345678')).to be true
    end

    it 'returns false for non-Mexico numbers' do
      expect(normalizer.handles_country?('5541988887777')).to be false
      expect(normalizer.handles_country?('5491155887766')).to be false
      expect(normalizer.handles_country?('14155551234')).to be false
    end
  end

  describe '#normalize' do
    context 'when number does not have the mobile prefix 1 (52)' do
      it 'adds the 1 prefix' do
        expect(normalizer.normalize('525512345678')).to eq('5215512345678')
        expect(normalizer.normalize('521234567890')).to eq('5211234567890')
      end
    end

    context 'when number already has the mobile prefix 1 (521)' do
      it 'returns the number unchanged' do
        expect(normalizer.normalize('5215512345678')).to eq('5215512345678')
        expect(normalizer.normalize('5211234567890')).to eq('5211234567890')
      end
    end

    context 'when number is not from Mexico' do
      it 'returns the number unchanged' do
        expect(normalizer.normalize('5541988887777')).to eq('5541988887777')
      end
    end
  end
end
