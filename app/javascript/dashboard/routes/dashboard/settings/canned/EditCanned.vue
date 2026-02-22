<script>
/* eslint no-console: 0 */
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Modal from '../../../../components/Modal.vue';
import FilePreviewInput from 'dashboard/components/widgets/FilePreviewInput.vue';

export default {
  components: {
    NextButton,
    Modal,
    WootMessageEditor,
    FilePreviewInput,
  },
  props: {
    id: { type: Number, default: null },
    edcontent: { type: String, default: '' },
    edshortCode: { type: String, default: '' },
    edcontentType: { type: String, default: 'markdown' },
    onClose: { type: Function, default: () => {} },
    // Array of initial files: [{ filename, blob_id }]
    initialFiles: { type: Array, default: () => [] },
    // Initial selected custom role id for visibility (null/empty => visible to all)
    initialCustomRoleId: { type: [Number, String], default: null },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      editCanned: {
        showAlert: false,
        showLoading: false,
      },
      shortCode: this.edshortCode,
      content: this.edcontent,
      contentType: this.edcontentType || 'markdown',
      attachmentIds: (this.initialFiles || []).map(f => f.blob_id),
      // Selected role id for visibility. Empty string means visible to all roles
      selectedRoleId: this.initialCustomRoleId || '',
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
    pageTitle() {
      return `${this.$t('CANNED_MGMT.EDIT.TITLE')} - ${this.edshortCode}`;
    },
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
    setPageName({ name }) {
      this.v$.content.$touch();
      this.content = name;
    },
    resetForm() {
      this.shortCode = '';
      this.content = '';
      this.contentType = 'markdown';
      this.attachmentIds = [];
      this.selectedRoleId = '';
      this.v$.shortCode.$reset();
      this.v$.content.$reset();
    },
    editCannedResponse() {
      const content =
        this.contentType === 'plain_text'
          ? String(this.content || '').replace(/\r\n?/g, '\n')
          : this.content;

      // Show loading on button
      this.editCanned.showLoading = true;
      // Make API Calls
      this.$store
        .dispatch('updateCannedResponse', {
          id: this.id,
          short_code: this.shortCode,
          content,
          content_type: this.contentType,
          blob_ids: this.attachmentIds,
          // Always include custom_role_id in updates so user can also clear it (set to null for All)
          custom_role_id: this.selectedRoleId ? this.selectedRoleId : null,
        })
        .then(() => {
          // Reset Form, Show success message
          this.editCanned.showLoading = false;
          useAlert(this.$t('CANNED_MGMT.EDIT.API.SUCCESS_MESSAGE'));
          // Refresh the canned responses list to get updated file data
          this.$store.dispatch('getCannedResponse');
          this.resetForm();
          setTimeout(() => {
            this.onClose();
          }, 10);
        })
        .catch(error => {
          this.editCanned.showLoading = false;
          const errorMessage =
            error?.message || this.$t('CANNED_MGMT.EDIT.API.ERROR_MESSAGE');
          useAlert(errorMessage);
        });
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header :header-title="pageTitle" />
      <form class="flex flex-col w-full" @submit.prevent="editCannedResponse()">
        <div class="w-full">
          <label :class="{ error: v$.shortCode.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.LABEL') }}
            <input
              v-model="shortCode"
              type="text"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.PLACEHOLDER')"
              @input="v$.shortCode.$touch"
            />
          </label>
        </div>

        <div class="w-full mt-2">
          <label>
            {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT_TYPE.LABEL') }}
            <select v-model="contentType">
              <option value="markdown">
                {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT_TYPE.MARKDOWN') }}
              </option>
              <option value="plain_text">
                {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT_TYPE.PLAIN_TEXT') }}
              </option>
            </select>
          </label>
          <p class="text-xs text-slate-600 dark:text-slate-400 mt-1">
            {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT_TYPE.HELP') }}
          </p>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT.LABEL') }}
          </label>
          <div v-if="contentType === 'plain_text'" class="editor-wrap">
            <textarea
              v-model="content"
              rows="8"
              class="w-full p-2 border border-slate-300 dark:border-slate-600 rounded-md bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
              :class="{ 'border-red-500': v$.content.$error }"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER')"
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
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER')"
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
              $t('CANNED_MGMT.EDIT.FORM.ATTACHMENTS_LABEL') ||
              $t('AUTOMATION.ATTACHMENT.LABEL_IDLE')
            }}
          </label>
          <FilePreviewInput
            v-model="attachmentIds"
            :initial-files="initialFiles"
          />
        </div>

        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('CANNED_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="onClose"
          />
          <NextButton
            type="submit"
            :label="$t('CANNED_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="
              v$.content.$invalid ||
              v$.shortCode.$invalid ||
              editCanned.showLoading
            "
            :is-loading="editCanned.showLoading"
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
