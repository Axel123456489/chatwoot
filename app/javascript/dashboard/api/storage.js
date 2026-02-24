/* global axios */
import ApiClient from './ApiClient';

class StorageAPI extends ApiClient {
  constructor() {
    super('storage', { accountScoped: true });
  }

  analyze({ force = false } = {}) {
    return axios.get(`${this.url}/analyze`, { params: { force, async: true } });
  }

  status() {
    return axios.get(`${this.url}/status`);
  }

  duplicates(limit = 50) {
    return axios.get(`${this.url}/duplicates`, { params: { limit } });
  }

  largestFiles(limit = 20) {
    return axios.get(`${this.url}/largest_files`, { params: { limit } });
  }

  cleanupOrphans() {
    return axios.post(`${this.url}/cleanup_orphans`);
  }

  cleanupStatus() {
    return axios.get(`${this.url}/cleanup_status`);
  }

  deduplicate() {
    return axios.post(`${this.url}/deduplicate`);
  }

  deduplicationStatus() {
    return axios.get(`${this.url}/deduplication_status`);
  }

  cancelDeduplication() {
    return axios.delete(`${this.url}/cancel_deduplication`);
  }

  cancelCleanup() {
    return axios.delete(`${this.url}/cancel_cleanup`);
  }
}

export default new StorageAPI();
