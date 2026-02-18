<script>
import { useAlert } from 'dashboard/composables';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InboxesAPI from '../../api/inboxes';

export default {
  name: 'WhatsAppCallingSettings',
  components: {
    SettingsSection,
    NextButton,
  },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isLoading: false,
      isSaving: false,
      formData: {
        calling_enabled: false,
        recording_enabled: false,
      },
      originalData: null,
    };
  },
  computed: {
    canSave() {
      return true;
    },
  },
  watch: {
    inbox() {
      this.loadSettings();
    },
  },
  mounted() {
    this.loadSettings();
  },
  methods: {
    loadSettings() {
      this.isLoading = true;

      try {
        if (!this.inbox) {
          throw new Error('Inbox not found');
        }

        this.formData = {
          calling_enabled: this.inbox.calling_enabled || false,
          recording_enabled:
            this.inbox.calling_config?.recording_enabled || false,
        };

        this.originalData = JSON.parse(JSON.stringify(this.formData));
      } catch (error) {
        console.error('Error loading calling settings:', error);
        useAlert(this.$t('WHATSAPP_CALLS.SETTINGS.ERROR_LOADING'));
      } finally {
        this.isLoading = false;
      }
    },

    async saveSettings() {
      if (!this.canSave) return;

      this.isSaving = true;

      try {
        const payload = {
          channel: {
            calling_enabled: this.formData.calling_enabled,
            calling_config: this.formData.calling_enabled
              ? {
                  recording_enabled: this.formData.recording_enabled,
                }
              : null,
          },
        };

        await InboxesAPI.updateChannel(this.inbox.id, payload);

        useAlert(this.$t('WHATSAPP_CALLS.SETTINGS.SUCCESS'));
        this.originalData = JSON.parse(JSON.stringify(this.formData));

        // Refresh inbox data
        this.$store.dispatch('inboxes/get');
      } catch (error) {
        console.error('Error saving calling settings:', error);
        useAlert(this.$t('WHATSAPP_CALLS.SETTINGS.ERROR_SAVING'));
      } finally {
        this.isSaving = false;
      }
    },

    resetForm() {
      if (this.originalData) {
        this.formData = JSON.parse(JSON.stringify(this.originalData));
      }
    },
  },
};
</script>

<template>
  <div class="mx-8">
    <SettingsSection
      :title="$t('WHATSAPP_CALLS.SETTINGS.TITLE')"
      :sub-title="$t('WHATSAPP_CALLS.SETTINGS.DESCRIPTION')"
    >
      <form @submit.prevent="saveSettings">
        <!-- Enable Calling -->
        <div class="mb-4">
          <label class="flex items-center">
            <input
              id="toggle-enable-calling"
              v-model="formData.calling_enabled"
              type="checkbox"
              class="ltr:mr-2 rtl:ml-2"
            />
            <span class="text-sm font-medium text-slate-800">
              {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_CALLING') }}
            </span>
          </label>
          <p class="text-xs text-slate-600 mt-1 ml-6">
            {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_CALLING_HELP') }}
          </p>
        </div>

        <!-- Enable Recording (only when calling is enabled) -->
        <div v-if="formData.calling_enabled" class="ml-6 mb-6">
          <label class="flex items-center">
            <input
              id="toggle-recording"
              v-model="formData.recording_enabled"
              type="checkbox"
              class="ltr:mr-2 rtl:ml-2"
            />
            <span class="text-sm font-medium text-slate-800">
              {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_RECORDING') }}
            </span>
          </label>
          <p class="text-xs text-slate-600 mt-1 ml-6">
            {{ $t('WHATSAPP_CALLS.SETTINGS.ENABLE_RECORDING_HELP') }}
          </p>
        </div>

        <NextButton
          type="submit"
          :label="$t('WHATSAPP_CALLS.SETTINGS.SAVE')"
          :is-loading="isSaving"
          :disabled="!canSave || isSaving"
        />
      </form>
    </SettingsSection>
  </div>
</template>
