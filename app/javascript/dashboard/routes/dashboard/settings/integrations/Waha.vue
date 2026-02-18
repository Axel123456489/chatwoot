<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Spinner from 'shared/components/Spinner.vue';
import integrationAPI from 'dashboard/api/integrations';

import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const configDialogRef = ref(null);
const deleteDialogRef = ref(null);
const integrationLoaded = ref(false);
const baseUrl = ref('');
const apiKey = ref('');
const isSubmitting = ref(false);
const isDeleting = ref(false);
const formError = ref('');

const integration = useFunctionGetter('integrations/getIntegration', 'waha');
const uiFlags = useMapGetter('integrations/getUIFlags');

// Get the current hook if exists
const currentHook = computed(() => {
  if (integration.value.enabled && integration.value.hooks?.length > 0) {
    return integration.value.hooks[0];
  }
  return null;
});

const openConfigDialog = () => {
  // Load existing settings when opening dialog
  if (currentHook.value) {
    baseUrl.value = currentHook.value.settings?.base_url || '';
    apiKey.value = currentHook.value.settings?.api_key || '';
  }
  if (configDialogRef.value) {
    configDialogRef.value.open();
  }
};

const openDeleteDialog = () => {
  if (deleteDialogRef.value) {
    deleteDialogRef.value.open();
  }
};

const hideConfigModal = () => {
  formError.value = '';
  isSubmitting.value = false;
};

const validateUrl = url => {
  try {
    new URL(url);
    return true;
  } catch {
    return false;
  }
};

const handleSubmit = async () => {
  try {
    formError.value = '';

    if (!baseUrl.value || !apiKey.value) {
      formError.value = t('INTEGRATION_SETTINGS.WAHA.FORM.REQUIRED_FIELDS');
      return;
    }

    if (!validateUrl(baseUrl.value)) {
      formError.value = t('INTEGRATION_SETTINGS.WAHA.FORM.INVALID_URL');
      return;
    }

    isSubmitting.value = true;

    const settings = {
      base_url: baseUrl.value.replace(/\/$/, ''),
      api_key: apiKey.value,
    };

    if (currentHook.value) {
      // Update existing hook
      await integrationAPI.updateHook(currentHook.value.id, { settings });
      useAlert(t('INTEGRATION_SETTINGS.WAHA.UPDATE_SUCCESS'));
    } else {
      // Create new hook
      await integrationAPI.createHook({
        app_id: 'waha',
        settings,
      });
      useAlert(t('INTEGRATION_SETTINGS.WAHA.SUCCESS'));
    }

    if (configDialogRef.value) {
      configDialogRef.value.close();
    }

    // Refresh integrations
    await store.dispatch('integrations/get');
  } catch (error) {
    formError.value =
      error.response?.data?.message ||
      error.message ||
      t('INTEGRATION_SETTINGS.WAHA.ERROR');
  } finally {
    isSubmitting.value = false;
  }
};

const handleDelete = async () => {
  if (!currentHook.value) return;

  try {
    isDeleting.value = true;
    await integrationAPI.deleteHook(currentHook.value.id);
    useAlert(t('INTEGRATION_SETTINGS.WAHA.DELETE_SUCCESS'));

    if (deleteDialogRef.value) {
      deleteDialogRef.value.close();
    }

    // Reset form
    baseUrl.value = '';
    apiKey.value = '';

    // Refresh integrations
    await store.dispatch('integrations/get');
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INTEGRATION_SETTINGS.WAHA.DELETE_ERROR')
    );
  } finally {
    isDeleting.value = false;
  }
};

const initializeIntegration = async () => {
  await store.dispatch('integrations/get');
  integrationLoaded.value = true;

  // Load existing settings
  if (currentHook.value) {
    baseUrl.value = currentHook.value.settings?.base_url || '';
    apiKey.value = currentHook.value.settings?.api_key || '';
  }
};

onMounted(() => {
  initializeIntegration();
});
</script>

<template>
  <div class="flex-grow flex-shrink p-4 overflow-auto max-w-6xl mx-auto">
    <div
      v-if="integrationLoaded && !uiFlags.isFetching"
      class="flex flex-col gap-6"
    >
      <!-- Integration Card -->
      <div
        class="flex flex-col items-start justify-between lg:flex-row lg:items-center p-6 outline outline-n-container outline-1 bg-n-alpha-3 rounded-md shadow gap-6"
      >
        <div
          class="flex items-start lg:items-center justify-start flex-1 m-0 gap-6 flex-col lg:flex-row"
        >
          <div class="flex h-16 w-16 items-center justify-center flex-shrink-0">
            <img
              :src="`/dashboard/images/integrations/${integration.id}.png`"
              class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3"
            />
            <img
              :src="`/dashboard/images/integrations/${integration.id}-dark.png`"
              class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3"
            />
          </div>
          <div>
            <h3 class="mb-1 text-xl font-medium text-n-slate-12">
              {{ integration.name }}
            </h3>
            <p class="text-n-slate-11 text-sm leading-6">
              {{ integration.description }}
            </p>
          </div>
        </div>
        <div class="flex justify-center items-center gap-2">
          <Button
            v-if="integration.enabled"
            faded
            ruby
            :label="$t('INTEGRATION_SETTINGS.DISCONNECT.BUTTON_TEXT')"
            @click="openDeleteDialog"
          />
          <Button
            :faded="integration.enabled"
            :teal="!integration.enabled"
            :label="
              integration.enabled
                ? $t('INTEGRATION_SETTINGS.WAHA.CONNECTED.UPDATE_SETTINGS')
                : $t('INTEGRATION_SETTINGS.CONNECT.BUTTON_TEXT')
            "
            @click="openConfigDialog"
          />
        </div>
      </div>

      <!-- Show connected info when enabled -->
      <div
        v-if="integration.enabled"
        class="p-6 outline outline-n-container outline-1 bg-n-alpha-3 rounded-md shadow"
      >
        <h4 class="text-lg font-medium text-n-slate-12 mb-2">
          {{ $t('INTEGRATION_SETTINGS.WAHA.CONNECTED.TITLE') }}
        </h4>
        <p class="text-sm text-n-slate-11 mb-4">
          {{ $t('INTEGRATION_SETTINGS.WAHA.CONNECTED.DESCRIPTION') }}
        </p>
        <div class="mb-4 p-3 bg-n-alpha-2 rounded text-sm">
          <p class="text-n-slate-11">
            <span class="font-medium">Server:</span>
            <span class="ml-2 font-mono">{{ baseUrl }}</span>
          </p>
        </div>
        <Button
          blue
          :label="$t('INTEGRATION_SETTINGS.WAHA.CONNECTED.CREATE_INBOX')"
          @click="router.push({ name: 'settings_inbox_new' })"
        />
      </div>

      <!-- Config Dialog -->
      <Dialog
        ref="configDialogRef"
        :title="$t('INTEGRATION_SETTINGS.WAHA.FORM.TITLE')"
        :is-loading="isSubmitting"
        @confirm="handleSubmit"
        @close="hideConfigModal"
      >
        <div class="flex flex-col gap-4">
          <Input
            v-model="baseUrl"
            :label="$t('INTEGRATION_SETTINGS.WAHA.FORM.BASE_URL.LABEL')"
            :placeholder="
              $t('INTEGRATION_SETTINGS.WAHA.FORM.BASE_URL.PLACEHOLDER')
            "
            :message="$t('INTEGRATION_SETTINGS.WAHA.FORM.BASE_URL.HELP')"
            message-type="info"
          />
          <Input
            v-model="apiKey"
            type="password"
            :label="$t('INTEGRATION_SETTINGS.WAHA.FORM.API_KEY.LABEL')"
            :placeholder="
              $t('INTEGRATION_SETTINGS.WAHA.FORM.API_KEY.PLACEHOLDER')
            "
            :message="$t('INTEGRATION_SETTINGS.WAHA.FORM.API_KEY.HELP')"
            message-type="info"
          />
          <p v-if="formError" class="text-n-ruby-9 text-sm">
            {{ formError }}
          </p>
        </div>
      </Dialog>

      <!-- Delete Confirmation Dialog -->
      <Dialog
        ref="deleteDialogRef"
        type="alert"
        :title="$t('INTEGRATION_SETTINGS.WAHA.DELETE.TITLE')"
        :description="$t('INTEGRATION_SETTINGS.WAHA.DELETE.MESSAGE')"
        :is-loading="isDeleting"
        @confirm="handleDelete"
      />
    </div>

    <div v-else class="flex items-center justify-center flex-1 h-full">
      <Spinner size="" color-scheme="primary" />
    </div>
  </div>
</template>
