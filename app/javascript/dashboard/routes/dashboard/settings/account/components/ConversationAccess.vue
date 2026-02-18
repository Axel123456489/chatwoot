<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const isEnabled = ref(false);

watch(
  currentAccount,
  () => {
    const { allow_agents_view_all_conversations } =
      currentAccount.value?.settings || {};
    isEnabled.value = Boolean(allow_agents_view_all_conversations);
  },
  { deep: true, immediate: true }
);

const updateAccountSettings = async settings => {
  try {
    await updateAccount(settings);
    useAlert(t('GENERAL_SETTINGS.FORM.CONVERSATION_ACCESS.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.CONVERSATION_ACCESS.API.ERROR'));
  }
};

const toggleConversationAccess = async () => {
  return updateAccountSettings({
    allow_agents_view_all_conversations: isEnabled.value,
  });
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.CONVERSATION_ACCESS.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.CONVERSATION_ACCESS.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggleConversationAccess" />
      </div>
    </template>
  </SectionLayout>
</template>
