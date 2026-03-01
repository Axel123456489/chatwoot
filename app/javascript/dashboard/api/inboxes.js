/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class Inboxes extends CacheEnabledApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'inbox';
  }

  getCampaigns(inboxId) {
    return axios.get(`${this.url}/${inboxId}/campaigns`);
  }

  deleteInboxAvatar(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/avatar`);
  }

  getAgentBot(inboxId) {
    return axios.get(`${this.url}/${inboxId}/agent_bot`);
  }

  setAgentBot(inboxId, botId) {
    return axios.post(`${this.url}/${inboxId}/set_agent_bot`, {
      agent_bot: botId,
    });
  }

  syncTemplates(inboxId) {
    return axios.post(`${this.url}/${inboxId}/sync_templates`);
  }

  createCSATTemplate(inboxId, template) {
    return axios.post(`${this.url}/${inboxId}/csat_template`, {
      template,
    });
  }

  getCSATTemplateStatus(inboxId) {
    return axios.get(`${this.url}/${inboxId}/csat_template`);
  }

  updateChannel(inboxId, channelData) {
    return axios.patch(
      `${this.url}/${inboxId}/update_channel_settings`,
      channelData
    );
  }

  getMetaCallingSettings(inboxId) {
    return axios.get(`${this.url}/${inboxId}/meta_calling_settings`);
  }
}

export default new Inboxes();
