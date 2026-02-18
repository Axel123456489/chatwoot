/* global axios */

import ApiClient from './ApiClient';

class WahaAPI extends ApiClient {
  constructor() {
    super('integrations/waha', { accountScoped: true });
  }

  getIntegration() {
    return axios.get(`${this.baseUrl()}/integrations/hooks`, {
      params: { app_id: 'waha' },
    });
  }
}

export default new WahaAPI();
