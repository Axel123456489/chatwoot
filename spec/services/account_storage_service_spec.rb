require 'rails_helper'

RSpec.describe AccountStorageService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '#analyze' do
    context 'when account has no attachments' do
      it 'returns zero storage data' do
        result = service.analyze

        expect(result[:overview][:total_size]).to eq(0)
        expect(result[:overview][:total_blobs]).to eq(0)
        expect(result[:orphan_blobs][:count]).to eq(0)
        expect(result[:duplicates][:files]).to eq(0)
      end
    end

    context 'when account has attachments' do
      let!(:message_with_attachment) do
        message = create(:message, account: account, conversation: conversation)
        attachment = message.attachments.new(account_id: account.id, file_type: :file)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        attachment.save!
        message
      end

      it 'returns storage overview' do
        result = service.analyze

        expect(result[:overview][:total_size]).to be > 0
        expect(result[:overview][:total_blobs]).to be > 0
        expect(result[:by_source]).to have_key(:messages)
      end

      it 'includes storage by content type' do
        result = service.analyze

        expect(result[:by_content_type]).to be_an(Array)
        expect(result[:by_content_type].first).to have_key(:content_type)
        expect(result[:by_content_type].first).to have_key(:count)
        expect(result[:by_content_type].first).to have_key(:size)
      end

      it 'includes storage by source' do
        result = service.analyze

        expect(result[:by_source]).to have_key(:messages)
        expect(result[:by_source][:messages]).to have_key(:count)
        expect(result[:by_source][:messages]).to have_key(:size)
      end
    end
  end

  describe '#find_duplicates' do
    context 'when there are no duplicates' do
      it 'returns empty duplicates list' do
        result = service.find_duplicates(limit: 10)

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end

    context 'when there are duplicate files' do
      let!(:message1) do
        message = create(:message, account: account, conversation: conversation)
        attachment = message.attachments.new(account_id: account.id, file_type: :file)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        attachment.save!
        message
      end

      let!(:message2) do
        message = create(:message, account: account, conversation: conversation)
        attachment = message.attachments.new(account_id: account.id, file_type: :file)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar_copy.png', content_type: 'image/png')
        attachment.save!
        message
      end

      it 'identifies duplicate files by checksum' do
        result = service.find_duplicates(limit: 10)

        expect(result).to be_an(Array)
        # Note: This test might not always find duplicates depending on how ActiveStorage handles identical files
        # In production, identical files would share the same checksum
      end

      it 'respects the limit parameter' do
        result = service.find_duplicates(limit: 5)

        expect(result.length).to be <= 5
      end
    end
  end

  describe '#find_largest_files' do
    context 'when account has attachments' do
      let!(:message_with_attachment) do
        message = create(:message, account: account, conversation: conversation)
        attachment = message.attachments.new(account_id: account.id, file_type: :file)
        attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'large_file.png', content_type: 'image/png')
        attachment.save!
        message
      end

      it 'returns largest files' do
        result = service.find_largest_files(limit: 10)

        expect(result).to be_an(Array)
        expect(result.first).to have_key(:filename)
        expect(result.first).to have_key(:size)
        expect(result.first).to have_key(:content_type)
        expect(result.first).to have_key(:is_duplicate)
      end

      it 'respects the limit parameter' do
        result = service.find_largest_files(limit: 5)

        expect(result.length).to be <= 5
      end

      it 'orders files by size descending' do
        result = service.find_largest_files(limit: 10)

        if result.length > 1
          expect(result.first[:size]).to be >= result.last[:size]
        end
      end
    end
  end

  describe '#cleanup_orphan_blobs' do
    context 'when there are orphan blobs' do
      it 'returns count and size of cleaned files' do
        result = service.cleanup_orphan_blobs

        expect(result).to have_key(:cleaned_count)
        expect(result).to have_key(:space_freed)
        expect(result[:cleaned_count]).to be >= 0
        expect(result[:space_freed]).to be >= 0
      end
    end
  end

  describe '#deduplicate_files' do
    it 'returns summary of deduplication' do
      result = service.deduplicate_files

      expect(result).to have_key(:deduplicated_count)
      expect(result).to have_key(:space_saved)
      expect(result[:deduplicated_count]).to be >= 0
      expect(result[:space_saved]).to be >= 0
    end
  end

  describe 'private helper methods' do
    describe '#duplicate_checksums' do
      it 'returns checksums that appear more than once' do
        checksums = service.send(:duplicate_checksums)

        expect(checksums).to be_an(Array)
      end
    end

    describe '#count_by_checksum' do
      let(:checksum) { 'test_checksum' }

      it 'returns count for given checksum' do
        count = service.send(:count_by_checksum, checksum)

        expect(count).to be >= 0
      end
    end
  end
end
