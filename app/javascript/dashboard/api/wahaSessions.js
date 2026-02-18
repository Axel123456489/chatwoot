/* global axios */
import ApiClient from './ApiClient';

class WahaSessionsAPI extends ApiClient {
  constructor() {
    super('waha_sessions', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  get(sessionId) {
    return axios.get(`${this.url}/${sessionId}`);
  }

  delete(sessionId, deleteInbox = false) {
    return axios.delete(`${this.url}/${sessionId}`, {
      params: { delete_inbox: deleteInbox },
    });
  }

  getStatus(sessionId) {
    return axios.get(`${this.url}/${sessionId}/status`);
  }

  getQRCode(sessionId, refresh = false) {
    return axios.get(`${this.url}/${sessionId}/qr_code`, {
      params: { refresh },
    });
  }

  restart(sessionId) {
    return axios.post(`${this.url}/${sessionId}/restart`);
  }

  logout(sessionId) {
    return axios.post(`${this.url}/${sessionId}/logout`);
  }

  recreateApp(sessionId) {
    return axios.post(`${this.url}/${sessionId}/recreate_app`);
  }

  updateConfig(sessionId, config) {
    return axios.patch(`${this.url}/${sessionId}/update_config`, config);
  }

  syncConfig(sessionId) {
    return axios.post(`${this.url}/${sessionId}/sync_config`);
  }
}

export default new WahaSessionsAPI();
