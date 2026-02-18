/* global axios */
import ApiClient from './ApiClient';

class StorageAPI extends ApiClient {
  constructor() {
    super('storage', { accountScoped: true });
  }

  analyze() {
    return axios.get(`${this.url}/analyze`);
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

  deduplicate() {
    return axios.post(`${this.url}/deduplicate`);
  }
}

export default new StorageAPI();
