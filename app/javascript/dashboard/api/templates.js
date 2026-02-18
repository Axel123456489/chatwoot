/* global axios */

import ApiClient from './ApiClient';

class TemplatesAPI extends ApiClient {
  constructor() {
    super('templates', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  getInboxes() {
    return axios.get(`${this.url}/inboxes`);
  }

  syncTemplates(inboxId) {
    // Use explicit inbox-scoped endpoint
    return axios.post(`${this.baseUrl()}/inboxes/${inboxId}/sync_templates`);
  }

  createTemplate(templateData, inboxId) {
    // Use the create_template endpoint under templates and include inbox_id in payload
    return axios.post(`${this.url}/create_template`, {
      template: {
        ...templateData,
        inbox_id: inboxId,
      },
    });
  }

  updateTemplate(inboxId, templateId, payload) {
    // PUT to inbox-scoped message_templates
    return axios.put(
      `${this.baseUrl()}/inboxes/${inboxId}/message_templates/${templateId}`,
      payload
    );
  }

  deleteTemplate(inboxId, templateId) {
    // DELETE inbox-scoped message_templates
    return axios.delete(
      `${this.baseUrl()}/inboxes/${inboxId}/message_templates/${templateId}`
    );
  }
}

export default new TemplatesAPI();
