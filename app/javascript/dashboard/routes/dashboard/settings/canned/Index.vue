<script setup>
import { useAlert } from 'dashboard/composables';
import AddCanned from './AddCanned.vue';
import EditCanned from './EditCanned.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import { computed, onMounted, ref, defineOptions } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import Button from 'dashboard/components-next/button/Button.vue';
import FileIcon from 'dashboard/components-next/icon/FileIcon.vue';

defineOptions({
  name: 'CannedResponseSettings',
});

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const { getPlainText } = useMessageFormatter();

const showAddPopup = ref(false);
const loading = ref({});
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const activeResponse = ref({});
const cannedResponseAPI = ref({ message: '' });

const sortOrder = ref('asc');
const records = computed(() =>
  getters.getSortedCannedResponses.value(sortOrder.value)
);
const uiFlags = computed(() => getters.getUIFlags.value);

const deleteConfirmText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.YES')} ${activeResponse.value.short_code}`
);

const deleteRejectText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.NO')} ${activeResponse.value.short_code}`
);

const deleteMessage = computed(() => {
  return ` ${activeResponse.value.short_code} ? `;
});

const toggleSort = () => {
  sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc';
};

const fetchCannedResponses = async () => {
  try {
    await store.dispatch('getCannedResponse');
  } catch (error) {
    // Ignore Error
  }
};

const fetchCustomRoles = async () => {
  try {
    // Load custom roles for visibility selector; ignore if module not present
    await store.dispatch('customRole/getCustomRole');
  } catch (e) {
    // ignore
  }
};

onMounted(() => {
  fetchCannedResponses();
  fetchCustomRoles();
});

const showAlertMessage = message => {
  loading[activeResponse.value.id] = false;
  activeResponse.value = {};
  cannedResponseAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  activeResponse.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  activeResponse.value = response;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteCannedResponse = async id => {
  try {
    await store.dispatch('deleteCannedResponse', id);
    showAlertMessage(t('CANNED_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CANNED_MGMT.DELETE.API.ERROR_MESSAGE');
    showAlertMessage(errorMessage);
  }
};

const confirmDeletion = () => {
  loading[activeResponse.value.id] = true;
  closeDeletePopup();
  deleteCannedResponse(activeResponse.value.id);
};

const tableHeaders = computed(() => {
  return [
    t('CANNED_MGMT.LIST.TABLE_HEADER.SHORT_CODE'),
    t('CANNED_MGMT.LIST.TABLE_HEADER.CONTENT'),
    t('CANNED_MGMT.LIST.TABLE_HEADER.ATTACHMENTS'),
    t('CANNED_MGMT.LIST.TABLE_HEADER.ACTIONS'),
  ];
});

const getFiles = item =>
  item?.files?.length ? item.files : item?.file_base_data || [];
const hasAttachments = item =>
  Array.isArray(getFiles(item)) && getFiles(item).length > 0;

const fileExtension = file => {
  let ext = '';
  if (file?.filename) {
    const parts = String(file.filename).split('.');
    if (parts.length > 1) ext = parts.pop();
  }
  if (!ext && file?.file_type) {
    const typeParts = String(file.file_type).split('/');
    if (typeParts.length > 1) ext = typeParts[1];
  }
  if (!ext) return '';
  ext = String(ext).toLowerCase();
  if (ext === 'jpeg') ext = 'jpg';
  return ext;
};

const uniqueAttachmentExtensions = item => {
  const list = getFiles(item);
  if (!list.length) return [];
  const exts = list.map(fileExtension).filter(Boolean);
  return [...new Set(exts)];
};
</script>

<template>
  <div class="flex-1 overflow-auto">
    <BaseSettingsHeader
      :title="$t('CANNED_MGMT.HEADER')"
      :description="$t('CANNED_MGMT.DESCRIPTION')"
      :link-text="$t('CANNED_MGMT.LEARN_MORE')"
      feature-name="canned_responses"
    >
      <template #actions>
        <Button
          icon="i-lucide-circle-plus"
          :label="$t('CANNED_MGMT.HEADER_BTN_TXT')"
          @click="openAddPopup"
        />
      </template>
    </BaseSettingsHeader>

    <div class="mt-6 flex-1">
      <woot-loading-state
        v-if="uiFlags.fetchingList"
        :message="$t('CANNED_MGMT.LOADING')"
      />
      <p
        v-else-if="!records.length"
        class="flex flex-col items-center justify-center h-full text-base text-n-slate-11 py-8"
      >
        {{ $t('CANNED_MGMT.LIST.404') }}
      </p>
      <table v-else class="min-w-full overflow-x-auto divide-y divide-n-weak">
        <thead>
          <th
            v-for="thHeader in tableHeaders"
            :key="thHeader"
            class="py-4 ltr:pr-4 rtl:pl-4 text-left font-semibold text-n-slate-11 last:text-right"
          >
            <span v-if="thHeader !== tableHeaders[0]">
              {{ thHeader }}
            </span>
            <button
              v-else
              class="flex items-center p-0 cursor-pointer"
              @click="toggleSort"
            >
              <span class="mb-0">
                {{ thHeader }}
              </span>
              <fluent-icon
                class="ml-2 size-4"
                :icon="sortOrder === 'desc' ? 'chevron-up' : 'chevron-down'"
              />
            </button>
          </th>
        </thead>
        <tbody class="divide-y divide-n-weak text-n-slate-11">
          <tr
            v-for="(cannedItem, index) in records"
            :key="cannedItem.short_code"
          >
            <td
              class="py-4 ltr:pr-4 rtl:pl-4 truncate max-w-xs font-medium"
              :title="cannedItem.short_code"
            >
              {{ cannedItem.short_code }}
            </td>
            <td class="py-4 ltr:pr-4 rtl:pl-4 md:break-all whitespace-normal">
              {{ getPlainText(cannedItem.content) }}
            </td>
            <td class="py-4 ltr:pr-4 rtl:pl-4">
              <div
                v-if="hasAttachments(cannedItem)"
                class="flex flex-wrap gap-2 items-center"
              >
                <template
                  v-for="ext in uniqueAttachmentExtensions(cannedItem)"
                  :key="ext"
                >
                  <div
                    class="inline-flex items-center gap-1 rounded border border-n-weak px-2 py-1 text-xs text-n-slate-11"
                  >
                    <FileIcon class="size-4" :file-type="ext" />
                    <span class="uppercase">{{ ext }}</span>
                  </div>
                </template>
              </div>
              <span v-else class="text-n-slate-9">—</span>
            </td>
            <td class="py-4 flex justify-end gap-1">
              <Button
                v-tooltip.top="$t('CANNED_MGMT.EDIT.BUTTON_TEXT')"
                icon="i-lucide-pen"
                slate
                xs
                faded
                @click="openEditPopup(cannedItem)"
              />
              <Button
                v-tooltip.top="$t('CANNED_MGMT.DELETE.BUTTON_TEXT')"
                icon="i-lucide-trash-2"
                xs
                ruby
                faded
                :is-loading="loading[cannedItem.id]"
                @click="openDeletePopup(cannedItem, index)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddCanned :on-close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditCanned
        v-if="showEditPopup"
        :id="activeResponse.id"
        :edshort-code="activeResponse.short_code"
        :edcontent="activeResponse.content"
        :edcontent-type="activeResponse.content_type"
        :on-close="hideEditPopup"
        :initial-files="activeResponse.files || []"
        :initial-custom-role-id="activeResponse.custom_role_id ?? ''"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CANNED_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('CANNED_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />
  </div>
</template>
