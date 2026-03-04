<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import SearchAPI from 'dashboard/api/search';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  currentChat: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['cancel']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const query = ref('');
const isSearching = ref(false);
const results = ref([]);
const selectedTarget = ref(null);
const isSubmitting = ref(false);

const v$ = useVuelidate({ selectedTarget: { required } }, { selectedTarget });

const accountId = computed(() => store.getters.getCurrentAccountId);

const formattedOptions = computed(() => {
  const currentInboxId = props.currentChat?.inbox_id;
  return results.value
    .filter(
      item =>
        item.id !== props.currentChat.id && item.inbox_id === currentInboxId
    )
    .map(item => {
      const name = item.meta?.sender?.name || '';
      const inbox = item.inbox_name || '';
      return {
        id: item.id,
        name: `#${item.id}${name ? ' · ' + name : ''}${inbox ? ' · ' + inbox : ''}`,
      };
    });
});

const sourceLabel = computed(() => {
  const name = props.currentChat?.meta?.sender?.name || '';
  const inbox = props.currentChat?.inbox_name || '';
  return `#${props.currentChat?.id || ''}${name ? ' · ' + name : ''}${inbox ? ' · ' + inbox : ''}`;
});

const selectedTargetId = computed(() => selectedTarget.value?.id || null);
const targetLabel = computed(() => selectedTarget.value?.name || '');

const fetchConversations = async () => {
  if (!query.value || query.value.trim().length < 2) {
    results.value = [];
    return;
  }
  isSearching.value = true;
  results.value = [];
  try {
    const { data } = await SearchAPI.conversations({ q: query.value, page: 1 });
    results.value = data?.payload?.conversations || [];
  } catch {
    // ignore
  } finally {
    isSearching.value = false;
  }
};

const debouncedSearch = debounce(fetchConversations, 300, false);

const onMultiselectSearch = q => {
  query.value = q;
  debouncedSearch();
};

// Cancel button inside the form — close the dialog then notify parent
const onCancel = () => {
  dialogRef.value?.close();
  emit('cancel');
};

// Dialog @close event (click outside / ESC) — dialog already closed, just notify parent
const onDialogClose = () => {
  emit('cancel');
};

const onSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  isSubmitting.value = true;
  try {
    await store.dispatch('mergeConversationMessages', {
      sourceId: props.currentChat.id,
      targetId: selectedTargetId.value,
    });
    useAlert(t('MERGE_MESSAGES.SUCCESS'));
    onCancel();
  } catch {
    useAlert(t('MERGE_MESSAGES.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(() => {
  dialogRef.value?.open();
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    :title="$t('MERGE_MESSAGES.TITLE')"
    :description="$t('MERGE_MESSAGES.DESC')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="onDialogClose"
  >
    <div class="flex flex-col gap-4">
      <!-- Target (kept) -->
      <div
        class="multiselect-wrap--medium"
        :class="{ error: v$.selectedTarget.$error }"
      >
        <label class="multiselect__label">
          {{ $t('MERGE_MESSAGES.TARGET_LABEL') }}
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
            <span>{{ $t('AGENT_MGMT.SEARCH.NO_RESULTS') }}</span>
          </template>
        </multiselect>
        <span v-if="v$.selectedTarget.$error" class="message">
          {{ $t('PRIMARY_REQUIRED_ERROR') }}
        </span>
      </div>

      <!-- Arrow + Source -->
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
            :disabled="true"
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

      <!-- Summary -->
      <div
        v-if="selectedTargetId"
        class="p-3 border rounded-md border-n-weak bg-n-alpha-2"
      >
        <p class="text-sm font-medium mb-2">
          {{ $t('MERGE_MESSAGES.SUMMARY_TITLE') }}
        </p>
        <ul class="space-y-1 text-sm">
          <li>
            <span class="after:content-[':']">
              {{ $t('MERGE_MESSAGES.SOURCE') }}
            </span>
            <span class="ml-1">{{ sourceLabel }}</span>
            <span class="ml-2 text-n-ruby-10">
              ({{ $t('MERGE_MESSAGES.WILL_BE_DELETED') }})
            </span>
          </li>
          <li>
            <span class="after:content-[':']">
              {{ $t('MERGE_MESSAGES.TARGET') }}
            </span>
            <span class="ml-1">{{ targetLabel }}</span>
            <span class="ml-2 text-n-green-10">
              ({{ $t('MERGE_MESSAGES.WILL_BE_KEPT') }})
            </span>
          </li>
        </ul>
        <p class="mt-2 text-xs">
          {{ $t('MERGE_MESSAGES.SUMMARY_NOTE') }}
        </p>
      </div>

      <!-- Actions -->
      <div class="flex justify-end gap-2">
        <Button
          variant="faded"
          color="slate"
          :label="$t('MERGE_MESSAGES.CANCEL')"
          @click="onCancel"
        />
        <Button
          :label="$t('MERGE_MESSAGES.SUBMIT')"
          :disabled="!selectedTargetId || isSubmitting"
          :is-loading="isSubmitting"
          @click="onSubmit"
        />
      </div>
    </div>
  </Dialog>
</template>
