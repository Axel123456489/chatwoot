require 'rails_helper'

RSpec.describe CannedResponse, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:custom_role).optional }
    it { is_expected.to have_many_attached(:files) }
  end

  describe 'validations' do
    subject { build(:canned_response, account: create(:account)) }

    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:short_code) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:content_type) }
    it { is_expected.to validate_uniqueness_of(:short_code).scoped_to(:account_id) }
    it { is_expected.to validate_inclusion_of(:content_type).in_array(%w[markdown plain_text]) }
  end

  describe 'custom_role association' do
    let(:account) { create(:account) }
    let(:custom_role) { create(:custom_role, account: account) }

    it 'can be created with a custom_role' do
      canned_response = create(:canned_response, account: account, custom_role: custom_role)
      expect(canned_response.custom_role).to eq(custom_role)
    end

    it 'can be created without a custom_role' do
      canned_response = create(:canned_response, account: account, custom_role: nil)
      expect(canned_response.custom_role).to be_nil
    end

    it 'can update custom_role after creation' do
      canned_response = create(:canned_response, account: account, custom_role: nil)
      canned_response.update(custom_role: custom_role)
      expect(canned_response.reload.custom_role).to eq(custom_role)
    end

    it 'can remove custom_role after creation' do
      canned_response = create(:canned_response, account: account, custom_role: custom_role)
      canned_response.update(custom_role: nil)
      expect(canned_response.reload.custom_role).to be_nil
    end
  end

  describe 'content_type' do
    let(:account) { create(:account) }

    it 'defaults to markdown when not specified' do
      canned_response = create(:canned_response, account: account)
      expect(canned_response.content_type).to eq('markdown')
    end

    it 'accepts markdown as content_type' do
      canned_response = create(:canned_response, account: account, content_type: 'markdown')
      expect(canned_response.content_type).to eq('markdown')
      expect(canned_response).to be_valid
    end

    it 'accepts plain_text as content_type' do
      canned_response = create(:canned_response, account: account, content_type: 'plain_text')
      expect(canned_response.content_type).to eq('plain_text')
      expect(canned_response).to be_valid
    end

    it 'rejects invalid content_type' do
      canned_response = build(:canned_response, account: account, content_type: 'invalid')
      expect(canned_response).not_to be_valid
      expect(canned_response.errors[:content_type]).to include('is not included in the list')
    end
  end
end
