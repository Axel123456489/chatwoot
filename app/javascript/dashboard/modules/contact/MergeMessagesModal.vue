<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SearchAPI from 'dashboard/api/search';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

export default {
  components: {
    NextButton,
  },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    currentChat: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['cancel', 'update:show'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      query: '',
      isSearching: false,
      results: [],
      // Use an object (like MergeContact) for the selected option
      selectedTarget: null,
      isSubmitting: false,
    };
  },
  validations() {
    return {
      selectedTarget: { required },
    };
  },
  computed: {
    localShow: {
      get() {
        return this.show;
      },
      set(value) {
        this.$emit('update:show', value);
      },
    },
    accountId() {
      return this.$store.getters.getCurrentAccountId;
    },
    // Filter out the current conversation and only show conversations from the same inbox
    formattedOptions() {
      const currentInboxId = this.currentChat?.inbox_id;
      return this.results
        .filter(
          item =>
            item.id !== this.currentChat.id && item.inbox_id === currentInboxId
        )
        .map(item => {
          const name = item.contact?.name || '';
          const inbox = item.inbox?.name || '';
          return {
            id: item.id,
            name: `#${item.id}${name ? ' · ' + name : ''}${inbox ? ' · ' + inbox : ''}`,
            raw: item,
          };
        });
    },
    sourceLabel() {
      const name = this.currentChat?.contact?.name || '';
      const inbox = this.currentChat?.inbox?.name || '';
      return `#${this.currentChat?.id || ''}${name ? ' · ' + name : ''}${inbox ? ' · ' + inbox : ''}`;
    },
    selectedTargetId() {
      return this.selectedTarget?.id || null;
    },
    targetLabel() {
      return this.selectedTarget?.name || '';
    },
  },
  created() {
    this.debouncedSearch = debounce(this.fetchConversations, 300, false);
  },
  methods: {
    onCancel() {
      this.$emit('update:show', false);
      this.$emit('cancel');
    },
    onMultiselectSearch(query) {
      this.query = query;
      this.debouncedSearch();
    },
    async fetchConversations() {
      if (!this.query || this.query.trim().length < 2) {
        this.results = [];
        return;
      }
      this.isSearching = true;
      this.results = [];
      try {
        const { data } = await SearchAPI.conversations({
          q: this.query,
          page: 1,
        });
        const conversations = data?.payload?.conversations || [];
        this.results = conversations;
      } catch (error) {
        // Ignore
      } finally {
        this.isSearching = false;
      }
    },
    async onSubmit() {
      const isFormValid = await this.v$.$validate();
      if (!isFormValid) return;

      this.isSubmitting = true;
      try {
        await this.$store.dispatch('mergeConversationMessages', {
          sourceId: this.currentChat.id,
          targetId: this.selectedTargetId,
        });

        useAlert(this.$t('MERGE_MESSAGES.SUCCESS'));

        const url = frontendURL(
          conversationUrl({
            accountId: this.accountId,
            id: this.selectedTargetId,
          })
        );
        this.onCancel();
        this.$router.push({ path: url });
      } catch (error) {
        useAlert(this.$t('MERGE_MESSAGES.ERROR'));
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>

<template>
  <woot-modal v-model:show="localShow" :on-close="onCancel">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="$t('MERGE_MESSAGES.TITLE')"
        :header-content="$t('MERGE_MESSAGES.DESC')"
      />
      <form class="w-full" @submit.prevent="onSubmit">
        <div class="w-full space-y-4">
          <!-- Target (kept) -->
          <div
            class="mt-1 multiselect-wrap--medium"
            :class="{ error: v$.selectedTarget.$error }"
          >
            <label class="multiselect__label">
              {{ $t('MERGE_MESSAGES.TARGET_LABEL') || 'Conversación destino' }}
              <woot-label
                :title="$t('MERGE_CONTACTS.PARENT.HELP_LABEL')"
                color-scheme="success"
                small
                class="ml-2"
              />
            </label>
            <multiselect
              v-model="selectedTarget"
              :options="formattedOptions"
              label="name"
              track-by="id"
              :internal-search="false"
              :clear-on-select="false"
              :show-labels="false"
              :placeholder="$t('MERGE_MESSAGES.PLACEHOLDER')"
              allow-empty
              :loading="isSearching"
              :max-height="150"
              open-direction="top"
              @search-change="onMultiselectSearch"
            >
              <template #singleLabel="{ option }">
                <span class="truncate">{{ option.name }}</span>
              </template>
              <template #option="{ option }">
                <span class="truncate">{{ option.name }}</span>
              </template>
              <template #noResult>
                <span>
                  {{ $t('AGENT_MGMT.SEARCH.NO_RESULTS') }}
                </span>
              </template>
            </multiselect>
            <span v-if="v$.selectedTarget.$error" class="message">
              {{
                $t('PRIMARY_REQUIRED_ERROR') || 'Please select a conversation'
              }}
            </span>
          </div>

          <!-- Arrow + Source (removed) block -->
          <div class="flex multiselect-wrap--medium">
            <div
              class="w-8 relative text-base text-n-strong after:content-[''] after:h-12 after:w-0 ltr:after:left-4 rtl:after:right-4 after:absolute after:border-l after:border-solid after:border-n-strong before:content-[''] before:h-0 before:w-4 ltr:before:left-4 rtl:before:right-4 before:top-12 before:absolute before:border-b before:border-solid before:border-n-strong"
            >
              <fluent-icon
                icon="arrow-up"
                class="absolute -top-1 ltr:left-2 rtl:right-2"
                size="17"
              />
            </div>
            <div class="flex flex-col w-full ltr:pl-8 rtl:pr-8">
              <label class="multiselect__label">
                {{ $t('MERGE_MESSAGES.SOURCE_LABEL') }}
                <woot-label
                  :title="$t('MERGE_CONTACTS.PRIMARY.HELP_LABEL')"
                  color-scheme="alert"
                  small
                  class="ml-2"
                />
              </label>
              <multiselect
                :model-value="{ id: currentChat?.id, name: sourceLabel }"
                disabled
                :options="[]"
                :show-labels="false"
                label="name"
                track-by="id"
              >
                <template #singleLabel="{ option }">
                  <span class="truncate">{{ option.name }}</span>
                </template>
              </multiselect>
            </div>
          </div>

          <!-- Summary block -->
          <div
            v-if="selectedTargetId"
            class="p-3 mt-1 border rounded-md border-n-weak bg-n-alpha-2"
          >
            <p class="text-sm text-n-slate-11 font-medium mb-2">
              {{ $t('MERGE_MESSAGES.SUMMARY_TITLE') }}
            </p>
            <ul class="space-y-1 text-sm">
              <li>
                <span class="text-n-slate-11 after:content-[':']">
                  {{ $t('MERGE_MESSAGES.SOURCE') }}
                </span>
                <span class="ml-1">{{ sourceLabel }}</span>
                <span
                  class="ml-2 text-n-ruby-10 inline-flex items-center before:content-['('] after:content-[')']"
                >
                  {{ $t('MERGE_MESSAGES.WILL_BE_DELETED') }}
                </span>
              </li>
              <li>
                <span class="text-n-slate-11 after:content-[':']">
                  {{ $t('MERGE_MESSAGES.TARGET') }}
                </span>
                <span class="ml-1">{{ targetLabel }}</span>
                <span
                  class="ml-2 text-n-green-10 inline-flex items-center before:content-['('] after:content-[')']"
                >
                  {{ $t('MERGE_MESSAGES.WILL_BE_KEPT') }}
                </span>
              </li>
            </ul>
            <p class="mt-2 text-xs text-n-slate-11">
              {{ $t('MERGE_MESSAGES.SUMMARY_NOTE') }}
            </p>
          </div>
        </div>

        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('MERGE_MESSAGES.CANCEL')"
            @click.prevent="onCancel"
          />
          <NextButton
            type="submit"
            :label="$t('MERGE_MESSAGES.SUBMIT')"
            :disabled="!selectedTargetId || isSubmitting"
            :is-loading="isSubmitting"
          />
        </div>
      </form>
    </div>
  </woot-modal>
</template>
