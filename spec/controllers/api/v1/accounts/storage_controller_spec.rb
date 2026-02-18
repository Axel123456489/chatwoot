require 'rails_helper'

RSpec.describe 'Storage API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/storage/analyze' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/storage/analyze"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/storage/analyze",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'returns storage analysis data' do
        get "/api/v1/accounts/#{account.id}/storage/analyze",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('overview')
        expect(json_response).to have_key('by_content_type')
        expect(json_response).to have_key('orphan_blobs')
        expect(json_response).to have_key('duplicates')
        expect(json_response).to have_key('by_source')
      end

      it 'returns proper structure for overview' do
        get "/api/v1/accounts/#{account.id}/storage/analyze",
            headers: admin.create_new_auth_token,
            as: :json

        overview = response.parsed_body['overview']

        expect(overview).to have_key('total_size')
        expect(overview).to have_key('total_blobs')
        expect(overview['total_size']).to be >= 0
        expect(overview['total_blobs']).to be >= 0
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/storage/duplicates' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/storage/duplicates"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'returns duplicates list' do
        get "/api/v1/accounts/#{account.id}/storage/duplicates",
            headers: admin.create_new_auth_token,
            params: { limit: 10 },
            as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('duplicates')
        expect(json_response['duplicates']).to be_an(Array)
      end

      it 'respects limit parameter' do
        get "/api/v1/accounts/#{account.id}/storage/duplicates",
            headers: admin.create_new_auth_token,
            params: { limit: 5 },
            as: :json

        expect(response).to have_http_status(:success)
        duplicates = response.parsed_body['duplicates']

        expect(duplicates.length).to be <= 5
      end

      it 'uses default limit when not specified' do
        get "/api/v1/accounts/#{account.id}/storage/duplicates",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        duplicates = response.parsed_body['duplicates']

        expect(duplicates.length).to be <= 50
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/storage/largest_files' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/storage/largest_files"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'returns largest files list' do
        get "/api/v1/accounts/#{account.id}/storage/largest_files",
            headers: admin.create_new_auth_token,
            params: { limit: 10 },
            as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('files')
        expect(json_response['files']).to be_an(Array)
      end

      it 'respects limit parameter' do
        get "/api/v1/accounts/#{account.id}/storage/largest_files",
            headers: admin.create_new_auth_token,
            params: { limit: 5 },
            as: :json

        expect(response).to have_http_status(:success)
        files = response.parsed_body['files']

        expect(files.length).to be <= 5
      end

      it 'includes file metadata' do
        get "/api/v1/accounts/#{account.id}/storage/largest_files",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        files = response.parsed_body['files']

        if files.any?
          file = files.first
          expect(file).to have_key('filename')
          expect(file).to have_key('size')
          expect(file).to have_key('content_type')
          expect(file).to have_key('is_duplicate')
        end
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/storage/cleanup_orphans' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/storage/cleanup_orphans"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/storage/cleanup_orphans",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'cleans up orphan files and returns summary' do
        post "/api/v1/accounts/#{account.id}/storage/cleanup_orphans",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('cleaned_count')
        expect(json_response).to have_key('space_freed')
        expect(json_response['cleaned_count']).to be >= 0
        expect(json_response['space_freed']).to be >= 0
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/storage/deduplicate' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/storage/deduplicate"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/storage/deduplicate",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'deduplicates files and returns summary' do
        post "/api/v1/accounts/#{account.id}/storage/deduplicate",
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('deduplicated_count')
        expect(json_response).to have_key('space_saved')
        expect(json_response['deduplicated_count']).to be >= 0
        expect(json_response['space_saved']).to be >= 0
      end
    end

    context 'when checksum is provided' do
      let(:checksum) { 'test_checksum_123' }

      it 'deduplicates only files with given checksum' do
        post "/api/v1/accounts/#{account.id}/storage/deduplicate",
             headers: admin.create_new_auth_token,
             params: { checksum: checksum },
             as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response).to have_key('deduplicated_count')
        expect(json_response).to have_key('space_saved')
      end
    end
  end
end
