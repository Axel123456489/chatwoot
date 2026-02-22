<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Modal from '../../../../components/Modal.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AutomationFileInput from 'dashboard/components/widgets/AutomationFileInput.vue';

export default {
  name: 'AddCanned',
  components: {
    NextButton,
    Modal,
    WootMessageEditor,
    AutomationFileInput,
  },
  props: {
    responseContent: {
      type: String,
      default: '',
    },
    onClose: {
      type: Function,
      default: () => {},
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      shortCode: '',
      content: this.responseContent || '',
      contentType: 'markdown',
      attachmentIds: [],
      // Selected role visibility for this canned response. Empty means visible to all roles
      selectedRoleId: '',
      addCanned: {
        showLoading: false,
        message: '',
      },
      show: true,
    };
  },
  validations: {
    shortCode: {
      required,
      minLength: minLength(2),
    },
    content: {
      required,
    },
  },
  computed: {
    // Current account id used for feature flag checks
    accountId() {
      return this.$store.getters.getCurrentAccountId;
    },
    // Whether custom roles feature is enabled on the current account
    isCustomRolesEnabled() {
      const isFeatureEnabled =
        this.$store.getters['accounts/isFeatureEnabledonAccount'];
      return typeof isFeatureEnabled === 'function'
        ? isFeatureEnabled(this.accountId, 'custom_roles')
        : false;
    },
    // List of available custom roles
    customRoles() {
      return this.$store.getters['customRole/getCustomRoles'] || [];
    },
  },
  methods: {
    resetForm() {
      this.shortCode = '';
      this.content = '';
      this.contentType = 'markdown';
      this.attachmentIds = [];
      this.selectedRoleId = '';
      this.v$.shortCode.$reset();
      this.v$.content.$reset();
    },
    addCannedResponse() {
      const content =
        this.contentType === 'plain_text'
          ? String(this.content || '').replace(/\r\n?/g, '\n')
          : this.content;

      // Show loading on button
      this.addCanned.showLoading = true;
      // Make API Calls
      this.$store
        .dispatch('createCannedResponse', {
          short_code: this.shortCode,
          content,
          content_type: this.contentType,
          blob_ids: this.attachmentIds,
          // Include custom_role_id only when a specific role is selected
          ...(this.selectedRoleId
            ? { custom_role_id: this.selectedRoleId }
            : {}),
        })
        .then(() => {
          // Reset Form, Show success message
          this.addCanned.showLoading = false;
          useAlert(this.$t('CANNED_MGMT.ADD.API.SUCCESS_MESSAGE'));
          // Refresh the canned responses list to get updated file data
          this.$store.dispatch('getCannedResponse');
          this.resetForm();
          this.onClose();
        })
        .catch(error => {
          this.addCanned.showLoading = false;
          const errorMessage =
            error?.message || this.$t('CANNED_MGMT.ADD.API.ERROR_MESSAGE');
          useAlert(errorMessage);
        });
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="$t('CANNED_MGMT.ADD.TITLE')"
        :header-content="$t('CANNED_MGMT.ADD.DESC')"
      />
      <form class="flex flex-col w-full" @submit.prevent="addCannedResponse()">
        <div class="w-full">
          <label :class="{ error: v$.shortCode.$error }">
            {{ $t('CANNED_MGMT.ADD.FORM.SHORT_CODE.LABEL') }}
            <input
              v-model="shortCode"
              type="text"
              :placeholder="$t('CANNED_MGMT.ADD.FORM.SHORT_CODE.PLACEHOLDER')"
              @blur="v$.shortCode.$touch"
            />
          </label>
        </div>

        <div class="w-full mt-2">
          <label>
            {{ $t('CANNED_MGMT.ADD.FORM.CONTENT_TYPE.LABEL') }}
            <select v-model="contentType">
              <option value="markdown">
                {{ $t('CANNED_MGMT.ADD.FORM.CONTENT_TYPE.MARKDOWN') }}
              </option>
              <option value="plain_text">
                {{ $t('CANNED_MGMT.ADD.FORM.CONTENT_TYPE.PLAIN_TEXT') }}
              </option>
            </select>
          </label>
          <p class="text-xs text-slate-600 dark:text-slate-400 mt-1">
            {{ $t('CANNED_MGMT.ADD.FORM.CONTENT_TYPE.HELP') }}
          </p>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.ADD.FORM.CONTENT.LABEL') }}
          </label>
          <div v-if="contentType === 'plain_text'" class="editor-wrap">
            <textarea
              v-model="content"
              rows="8"
              class="w-full p-2 border border-slate-300 dark:border-slate-600 rounded-md bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
              :class="{ 'border-red-500': v$.content.$error }"
              :placeholder="$t('CANNED_MGMT.ADD.FORM.CONTENT.PLACEHOLDER')"
              @blur="v$.content.$touch"
            />
          </div>
          <div v-else class="editor-wrap">
            <WootMessageEditor
              v-model="content"
              class="message-editor [&>div]:px-1"
              :class="{ editor_warning: v$.content.$error }"
              enable-variables
              :enable-canned-responses="false"
              :placeholder="$t('CANNED_MGMT.ADD.FORM.CONTENT.PLACEHOLDER')"
              @blur="v$.content.$touch"
            />
          </div>
        </div>

        <!-- Custom role visibility selector (shown only when feature enabled and roles exist) -->
        <div
          v-if="isCustomRolesEnabled && customRoles.length"
          class="w-full mt-2"
        >
          <label>
            {{ $t('CANNED_MGMT.ROLE_VISIBILITY.LABEL') }}
            <select v-model="selectedRoleId">
              <option value="">
                {{ $t('CANNED_MGMT.ROLE_VISIBILITY.ALL') }}
              </option>
              <option
                v-for="role in customRoles"
                :key="role.id"
                :value="role.id"
              >
                {{ role.name }}
              </option>
            </select>
          </label>
        </div>

        <div class="w-full mt-2">
          <label>
            {{
              $t('CANNED_MGMT.ADD.FORM.ATTACHMENTS_LABEL') ||
              $t('AUTOMATION.ATTACHMENT.LABEL_IDLE')
            }}
          </label>
          <AutomationFileInput v-model="attachmentIds" />
        </div>

        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('CANNED_MGMT.ADD.CANCEL_BUTTON_TEXT')"
            @click.prevent="onClose"
          />
          <NextButton
            type="submit"
            :label="$t('CANNED_MGMT.ADD.FORM.SUBMIT')"
            :disabled="
              v$.content.$invalid ||
              v$.shortCode.$invalid ||
              addCanned.showLoading
            "
            :is-loading="addCanned.showLoading"
          />
        </div>
      </form>
    </div>
  </Modal>
</template>

<style scoped lang="scss">
::v-deep {
  .ProseMirror-menubar {
    @apply hidden;
  }

  .ProseMirror-woot-style {
    @apply min-h-[12.5rem];

    p {
      @apply text-base;
    }
  }
}
</style>
