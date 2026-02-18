<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import WahaSessionsAPI from 'dashboard/api/wahaSessions';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

export default {
  components: {
    NextButton,
    Spinner,
  },
  data() {
    return {
      inboxName: '',
      isCreating: false,
      integrationLoading: true,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
      getIntegration: 'integrations/getIntegration',
    }),
    wahaIntegration() {
      return this.getIntegration('waha', {});
    },
    integrationEnabled() {
      // Check if integration is enabled AND has hooks configured
      return (
        this.wahaIntegration.enabled && this.wahaIntegration.hooks?.length > 0
      );
    },
  },
  mounted() {
    this.loadIntegration();
  },
  methods: {
    async loadIntegration() {
      try {
        await this.$store.dispatch('integrations/get');
      } catch (error) {
        // Silent fail - integrationEnabled will be false
      } finally {
        this.integrationLoading = false;
      }
    },
    goToIntegrationSettings() {
      router.push({
        name: 'settings_integrations_waha',
      });
    },
    async createChannel() {
      if (!this.inboxName.trim()) {
        useAlert(this.$t('INBOX_MGMT.ADD.WAHA.NAME_REQUIRED'));
        return;
      }

      try {
        this.isCreating = true;

        // Create WAHA session (creates API channel + inbox)
        const response = await WahaSessionsAPI.create({
          name: this.inboxName.trim(),
        });

        const sessionId = response.data.id;
        const inboxId = response.data.inbox?.id;

        // Navigate to QR code page
        router.replace({
          name: 'settings_inbox_waha_qr',
          params: { session_id: sessionId },
          query: { inbox_id: inboxId },
        });
      } catch (error) {
        const errorMessage =
          parseAPIErrorResponse(error) ||
          this.$t('INBOX_MGMT.ADD.WAHA.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      } finally {
        this.isCreating = false;
      }
    },
  },
};
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-6 space-y-6">
    <div class="mb-6">
      <h2 class="text-2xl font-semibold text-slate-900 dark:text-slate-100">
        {{ $t('INBOX_MGMT.ADD.WAHA.TITLE') }}
      </h2>
      <p class="text-sm text-slate-600 dark:text-slate-300 mt-1">
        {{ $t('INBOX_MGMT.ADD.WAHA.DESC') }}
      </p>
    </div>

    <div v-if="integrationLoading" class="flex items-center justify-center p-8">
      <Spinner size="" color-scheme="primary" />
    </div>

    <div
      v-else-if="!integrationEnabled"
      class="bg-yellow-50 dark:bg-amber-900/30 border border-yellow-200 dark:border-amber-800 rounded-lg p-6"
    >
      <h3
        class="text-lg font-semibold text-yellow-800 dark:text-amber-200 mb-2"
      >
        {{ $t('INBOX_MGMT.ADD.WAHA.INTEGRATION_NOT_ENABLED_TITLE') }}
      </h3>
      <p
        class="text-sm text-yellow-700 dark:text-amber-100 mb-4 leading-relaxed"
      >
        {{ $t('INBOX_MGMT.ADD.WAHA.INTEGRATION_NOT_ENABLED_MESSAGE') }}
      </p>
      <NextButton
        variant="smooth"
        size="medium"
        @click="goToIntegrationSettings"
      >
        {{ $t('INBOX_MGMT.ADD.WAHA.GO_TO_INTEGRATION_SETTINGS') }}
      </NextButton>
    </div>

    <form v-else class="space-y-6" @submit.prevent="createChannel()">
      <div class="space-y-2">
        <label
          class="block text-sm font-medium text-slate-800 dark:text-slate-100"
        >
          {{ $t('INBOX_MGMT.ADD.WAHA.INBOX_NAME.LABEL') }}
        </label>
        <input
          v-model="inboxName"
          type="text"
          class="w-full rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950 text-slate-900 dark:text-slate-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
          :placeholder="$t('INBOX_MGMT.ADD.WAHA.INBOX_NAME.PLACEHOLDER')"
        />
      </div>

      <div class="space-y-2">
        <h4 class="font-semibold text-slate-900 dark:text-slate-100">
          {{ $t('INBOX_MGMT.ADD.WAHA.WHAT_IS_WAHA_TITLE') }}
        </h4>
        <p class="text-sm text-slate-700 dark:text-slate-300 leading-relaxed">
          {{ $t('INBOX_MGMT.ADD.WAHA.WHAT_IS_WAHA_DESCRIPTION') }}
        </p>
        <ul
          class="text-sm text-slate-700 dark:text-slate-300 list-disc list-inside space-y-1"
        >
          <li>{{ $t('INBOX_MGMT.ADD.WAHA.FEATURES.NO_OFFICIAL_API') }}</li>
          <li>{{ $t('INBOX_MGMT.ADD.WAHA.FEATURES.QR_CODE') }}</li>
          <li>{{ $t('INBOX_MGMT.ADD.WAHA.FEATURES.MULTI_DEVICE') }}</li>
        </ul>
      </div>

      <div class="flex items-center justify-start">
        <NextButton
          :disabled="!inboxName.trim() || isCreating"
          :loading="isCreating"
        >
          {{ $t('INBOX_MGMT.ADD.WAHA.CREATE_CHANNEL') }}
        </NextButton>
      </div>
    </form>
  </div>
</template>
