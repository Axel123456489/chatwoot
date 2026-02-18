/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  get({ searchKey }) {
    const url = searchKey ? `${this.url}?search=${searchKey}` : this.url;
    return axios.get(url);
  }

  async create(payload) {
    const data = {
      canned_response: {
        short_code: payload.short_code,
        content: payload.content,
        ...(Object.prototype.hasOwnProperty.call(payload, 'content_type')
          ? { content_type: payload.content_type }
          : {}),
        ...(Object.prototype.hasOwnProperty.call(payload, 'custom_role_id')
          ? { custom_role_id: payload.custom_role_id }
          : {}),
      },
    };

    // Include blob_ids in request body, not query params
    if (Object.prototype.hasOwnProperty.call(payload, 'blob_ids')) {
      data.blob_ids = payload.blob_ids;
    }
    if (Object.prototype.hasOwnProperty.call(payload, 'blob_id')) {
      data.blob_id = payload.blob_id;
    }

    return axios.post(this.url, data);
  }

  async update(id, payload) {
    const data = { canned_response: {} };
    if (Object.prototype.hasOwnProperty.call(payload, 'short_code')) {
      data.canned_response.short_code = payload.short_code;
    }
    if (Object.prototype.hasOwnProperty.call(payload, 'content')) {
      data.canned_response.content = payload.content;
    }
    if (Object.prototype.hasOwnProperty.call(payload, 'content_type')) {
      data.canned_response.content_type = payload.content_type;
    }
    if (Object.prototype.hasOwnProperty.call(payload, 'custom_role_id')) {
      data.canned_response.custom_role_id = payload.custom_role_id;
    }

    // Include blob_ids in request body, not query params
    // This ensures empty arrays are properly sent to remove all attachments
    if (Object.prototype.hasOwnProperty.call(payload, 'blob_ids')) {
      data.blob_ids = payload.blob_ids;
    }
    if (Object.prototype.hasOwnProperty.call(payload, 'blob_id')) {
      data.blob_id = payload.blob_id;
    }

    return axios.patch(`${this.url}/${id}`, data);
  }
}

export default new CannedResponse();
