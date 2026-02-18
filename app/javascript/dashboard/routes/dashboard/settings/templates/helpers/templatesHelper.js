import TemplatesAPI from 'dashboard/api/templates';

export const getTemplates = async params => {
  const response = await TemplatesAPI.get(params);
  return response.data;
};

export const syncTemplates = async inboxId => {
  const response = await TemplatesAPI.syncTemplates(inboxId);
  return response.data;
};

export const createTemplate = async (templateData, inboxId) => {
  const response = await TemplatesAPI.createTemplate(templateData, inboxId);
  return response.data;
};

export const updateTemplate = async (inboxId, templateId, templateData) => {
  const response = await TemplatesAPI.updateTemplate(inboxId, templateId, {
    template: templateData,
  });
  return response.data;
};

export const deleteTemplate = async (templateId, inboxId) => {
  const response = await TemplatesAPI.deleteTemplate(inboxId, templateId);
  return response.data;
};

export const getWhatsAppInboxes = async () => {
  const response = await TemplatesAPI.getInboxes();
  // Backend returns { payload: [...] }
  return response.data?.payload || [];
};
