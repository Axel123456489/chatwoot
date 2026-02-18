<!-- eslint-disable vue/no-bare-strings-in-template -->
<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';

import Button from 'dashboard/components-next/button/Button.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CreateTemplate from './CreateTemplate.vue';
import {
  getTemplates,
  syncTemplates,
  getWhatsAppInboxes,
  deleteTemplate as deleteTemplateAPI,
} from './helpers/templatesHelper';

const { t } = useI18n();
const { isAdmin } = useAdmin();

const isLoading = ref(false);
const templates = ref([]);
const showCreatePopup = ref(false);
const showEditPopup = ref(false);
const editingTemplate = ref(null);
const showInboxSelector = ref(false);
const showViewModal = ref(false);
const selectedTemplate = ref(null);
const showDeletePopup = ref(false);
const selectedToDelete = ref(null);
const isInitialized = ref(false);

const isSyncing = ref(false);
const whatsappInboxes = ref([]);
const selectedInbox = ref(null);

// Pagination state
const currentPage = ref(1);
const totalEntries = ref(0);
const perPage = ref(10);

const selectedContent = ref('all');
const selectedChannel = ref('all');
const selectedLanguage = ref('all');
// New filters
const searchQuery = ref('');
const selectedStatus = ref('all'); // all | approved | pending | rejected

const contentFilterOptions = computed(() => [
  { value: 'all', label: t('SETTINGS.TEMPLATES.FILTERS.CONTENT') },
  { value: 'general', label: t('SETTINGS.TEMPLATES.FILTERS.OPTIONS.GENERAL') },
  {
    value: 'marketing',
    label: t('SETTINGS.TEMPLATES.FILTERS.OPTIONS.MARKETING'),
  },
  { value: 'utility', label: t('SETTINGS.TEMPLATES.FILTERS.OPTIONS.UTILITY') },
  {
    value: 'authentication',
    label: t('SETTINGS.TEMPLATES.FILTERS.OPTIONS.AUTHENTICATION'),
  },
]);

const channelFilterOptions = computed(() => [
  { value: 'all', label: t('SETTINGS.TEMPLATES.FILTERS.CHANNEL') },
  {
    value: 'whatsapp',
    label: t('SETTINGS.TEMPLATES.FILTERS.CHANNEL_OPTIONS.WHATSAPP'),
  },
  {
    value: 'telegram',
    label: t('SETTINGS.TEMPLATES.FILTERS.CHANNEL_OPTIONS.TELEGRAM'),
  },
  {
    value: 'email',
    label: t('SETTINGS.TEMPLATES.FILTERS.CHANNEL_OPTIONS.EMAIL'),
  },
  { value: 'sms', label: t('SETTINGS.TEMPLATES.FILTERS.CHANNEL_OPTIONS.SMS') },
]);

const languageFilterOptions = computed(() => [
  { value: 'all', label: t('SETTINGS.TEMPLATES.FILTERS.LANGUAGE') },
  {
    value: 'en',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.ENGLISH'),
  },
  {
    value: 'es',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.SPANISH'),
  },
  {
    value: 'fr',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.FRENCH'),
  },
  {
    value: 'de',
    label: t('SETTINGS.TEMPLATES.CREATE_MODAL.FIELDS.LANGUAGE.OPTIONS.GERMAN'),
  },
  {
    value: 'pt',
    label: t('SETTINGS.TEMPLATES.FILTERS.LANGUAGE_OPTIONS.PORTUGUESE'),
  },
]);

const filters = computed(() => ({
  category: selectedContent.value !== 'all' ? selectedContent.value : undefined,
  channel_type:
    selectedChannel.value !== 'all' ? selectedChannel.value : undefined,
  language:
    selectedLanguage.value !== 'all' ? selectedLanguage.value : undefined,
  inbox_id: selectedInbox.value ? selectedInbox.value.id : undefined,
  search: searchQuery.value?.trim() ? searchQuery.value.trim() : undefined,
  status: selectedStatus.value !== 'all' ? selectedStatus.value : undefined,
  page: currentPage.value,
}));

// Templates are now filtered by backend, so we just return them directly
const filteredTemplates = computed(() => templates.value);

const isSyncButtonDisabled = computed(() => {
  const hasNoInboxes = whatsappInboxes.value.length === 0;
  const hasNoInboxSelected = !selectedInbox.value;
  return hasNoInboxes || hasNoInboxSelected;
});

async function fetchTemplates(filterParams = {}) {
  isLoading.value = true;
  try {
    const response = await getTemplates(filterParams);
    // Check if response has payload and meta structure
    if (response.payload) {
      templates.value = response.payload;
      if (response.meta) {
        totalEntries.value = response.meta.total_entries || 0;
        // Only update currentPage if it's different to avoid watch loops
        const serverPage = response.meta.current_page || 1;
        if (currentPage.value !== serverPage) {
          currentPage.value = serverPage;
        }
        perPage.value = response.meta.per_page || 10;
      }
    } else {
      // Fallback for direct array response
      templates.value = Array.isArray(response) ? response : [];
    }
  } catch (_error) {
    useAlert(t('SETTINGS.TEMPLATES.API.FETCH_ERROR'));
    templates.value = [];
    totalEntries.value = 0;
  } finally {
    isLoading.value = false;
  }
}

// Debounced refetch to avoid too many API calls
const debouncedRefetch = debounce(() => {
  currentPage.value = 1;
  fetchTemplates(filters.value);
}, 300);

const handleSyncTemplates = async (inboxId = null) => {
  if (whatsappInboxes.value.length === 0) {
    useAlert(t('SETTINGS.TEMPLATES.SYNC.TOOLTIP.NO_INBOXES'));
    return;
  }

  // If no inbox specified, require one to be selected
  if (!inboxId) {
    if (selectedInbox.value) {
      inboxId = selectedInbox.value.id;
    } else {
      useAlert(t('SETTINGS.TEMPLATES.SYNC.TOOLTIP.SELECT_INBOX'));
      return;
    }
  }

  isSyncing.value = true;
  try {
    await syncTemplates(inboxId);
    useAlert(t('SETTINGS.TEMPLATES.SYNC.STARTED'));

    // Refresh templates after a short delay
    setTimeout(() => {
      // Preserve current filters (including selectedInbox)
      fetchTemplates(filters.value);
    }, 3000);
  } catch (_error) {
    useAlert(t('SETTINGS.TEMPLATES.SYNC.ERROR'));
  } finally {
    isSyncing.value = false;
    showInboxSelector.value = false;
  }
};

const openCreatePopup = () => {
  showCreatePopup.value = true;
};

const hideCreatePopup = () => {
  showCreatePopup.value = false;
};

const openEditPopup = template => {
  editingTemplate.value = template;
  showEditPopup.value = true;
};

const hideEditPopup = () => {
  showEditPopup.value = false;
  editingTemplate.value = null;
};

const onTemplateCreated = () => {
  // Refresh templates after creation
  setTimeout(() => {
    fetchTemplates(filters.value);
  }, 1000);
};

const viewTemplate = template => {
  selectedTemplate.value = template;
  showViewModal.value = true;
};

const closeViewModal = () => {
  showViewModal.value = false;
  selectedTemplate.value = null;
};

const openDelete = template => {
  showDeletePopup.value = true;
  selectedToDelete.value = template;
};

const closeDelete = () => {
  showDeletePopup.value = false;
  selectedToDelete.value = null;
};

async function deleteTemplate(template) {
  if (!template.id) {
    useAlert(t('SETTINGS.TEMPLATES.DELETE.ERROR_INVALID'));
    return;
  }

  try {
    // Find the inbox for this template
    const inbox = whatsappInboxes.value.find(i => i.id === template.inbox_id);
    if (!inbox) {
      useAlert(t('SETTINGS.TEMPLATES.DELETE.ERROR_NO_INBOX'));
      return;
    }

    // Call delete API
    await deleteTemplateAPI(template.id, inbox.id);
    useAlert(t('SETTINGS.TEMPLATES.DELETE.SUCCESS'));

    // Refresh templates
    fetchTemplates(filters.value);
  } catch (_error) {
    useAlert(t('SETTINGS.TEMPLATES.DELETE.ERROR'));
  }
}

const confirmDeletion = async () => {
  if (selectedToDelete.value) {
    await deleteTemplate(selectedToDelete.value);
  }
  closeDelete();
};

const fetchWhatsAppInboxes = async () => {
  try {
    const inboxes = await getWhatsAppInboxes();
    whatsappInboxes.value = inboxes;
  } catch (_error) {
    // Ignore errors while loading inbox filters; sync actions will surface errors separately
  }
};

const getStatusColor = status => {
  switch (status) {
    case 'approved':
      return 'text-green-600';
    case 'pending':
      return 'text-yellow-600';
    case 'rejected':
      return 'text-red-600';
    default:
      return 'text-gray-600';
  }
};

// TODO: fix me
const formatCategory = category => {
  if (!category) return '';
  const normalized = String(category).toUpperCase();
  const key = `SETTINGS.TEMPLATES.CATEGORIES.${normalized}`;
  const translated = t(key);
  if (translated !== key) {
    return translated;
  }

  return normalized
    .replace(/_/g, ' ')
    .toLowerCase()
    .replace(/\b\w/g, char => char.toUpperCase());
};

const getTemplateIcon = category => {
  const normalized = String(category || '').toLowerCase();
  switch (normalized) {
    case 'marketing':
      return 'i-lucide-megaphone';
    case 'authentication':
      return 'i-lucide-shield-check';
    case 'utility':
      return 'i-lucide-settings';
    default:
      return 'i-lucide-message-square';
  }
};

const getStatusLabel = status => {
  switch (status) {
    case 'approved':
      return t('SETTINGS.TEMPLATES.STATUS.APPROVED');
    case 'pending':
      return t('SETTINGS.TEMPLATES.STATUS.PENDING_REVIEW');
    case 'rejected':
      return t('SETTINGS.TEMPLATES.STATUS.REJECTED');
    default:
      return status;
  }
};

// Group templates by status for "All" view
const groupedByStatus = computed(() => {
  const groups = {
    approved: [],
    pending: [],
    rejected: [],
  };
  (templates.value || []).forEach(templateRecord => {
    const key = (templateRecord.status || 'pending').toLowerCase();
    if (groups[key]) groups[key].push(templateRecord);
  });
  return groups;
});

// Watch for filter changes and refetch templates
watch(
  [
    selectedContent,
    selectedChannel,
    selectedLanguage,
    selectedInbox,
    searchQuery,
    selectedStatus,
  ],
  () => {
    if (isInitialized.value) {
      debouncedRefetch();
    }
  },
  { deep: true, flush: 'post' }
);

// Watch for page changes
watch(
  currentPage,
  () => {
    if (isInitialized.value) {
      fetchTemplates(filters.value);
    }
  },
  { flush: 'post' }
);

const totalPages = computed(() => {
  return Math.ceil(totalEntries.value / perPage.value);
});

// Add pagination methods
const goToPage = page => {
  if (page >= 1 && page <= totalPages.value) {
    currentPage.value = page;
  }
};

const nextPage = () => {
  if (currentPage.value < totalPages.value) {
    currentPage.value += 1;
  }
};

const prevPage = () => {
  if (currentPage.value > 1) {
    currentPage.value -= 1;
  }
};

const pageNumbers = computed(() => {
  const pages = [];
  const maxPagesToShow = 5;
  const total = totalPages.value;

  if (total <= maxPagesToShow) {
    // Show all pages if total is less than max
    for (let i = 1; i <= total; i += 1) {
      pages.push(i);
    }
  } else {
    // Show first, current, and last pages with ellipsis
    pages.push(1);

    if (currentPage.value > 3) {
      pages.push('...');
    }

    // Show pages around current page
    const start = Math.max(2, currentPage.value - 1);
    const end = Math.min(total - 1, currentPage.value + 1);

    for (let i = start; i <= end; i += 1) {
      if (!pages.includes(i)) {
        pages.push(i);
      }
    }

    if (currentPage.value < total - 2) {
      pages.push('...');
    }

    if (!pages.includes(total)) {
      pages.push(total);
    }
  }

  return pages;
});

onMounted(async () => {
  await fetchWhatsAppInboxes();
  await fetchTemplates(filters.value);
  isInitialized.value = true;
});
</script>

<template>
  <SettingsLayout
    :no-records-found="!filteredTemplates.length && !isLoading"
    :no-records-message="$t('SETTINGS.TEMPLATES.LIST.404')"
    :is-loading="isLoading"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('SETTINGS.TEMPLATES.HEADER.TITLE')"
        :description="$t('SETTINGS.TEMPLATES.HEADER.DESCRIPTION')"
        :link-text="$t('SETTINGS.TEMPLATES.LEARN_MORE_ABOUT_TEMPLATES')"
        feature-name="templates"
      >
        <template #actions>
          <div class="flex items-center gap-3">
            <div class="relative">
              <Button
                icon="i-lucide-refresh-cw"
                slate
                :label="t('SETTINGS.TEMPLATES.SYNC.BUTTON')"
                :is-loading="isSyncing"
                :disabled="isSyncButtonDisabled"
                @click="() => handleSyncTemplates()"
              />
              <div
                v-if="isSyncButtonDisabled && !isSyncing"
                class="absolute -top-8 left-1/2 transform -translate-x-1/2 bg-n-dark-4 text-white text-xs px-2 py-1 rounded whitespace-nowrap z-10"
              >
                {{
                  whatsappInboxes.length === 0
                    ? t('SETTINGS.TEMPLATES.SYNC.TOOLTIP.NO_INBOXES')
                    : t('SETTINGS.TEMPLATES.SYNC.TOOLTIP.SELECT_INBOX')
                }}
              </div>
            </div>
            <Button
              v-if="isAdmin"
              icon="i-lucide-plus"
              blue
              :label="t('SETTINGS.TEMPLATES.ACTIONS.NEW_TEMPLATE')"
              @click="openCreatePopup"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <!-- Search and Status Filters -->
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <div class="relative flex-1 min-w-[240px] max-w-md">
          <span
            class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-n-slate-11 size-4"
          />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('SETTINGS.TEMPLATES.SEARCH.PLACEHOLDER')"
            class="w-full pl-9 pr-3 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5"
          />
        </div>
        <div class="relative w-56">
          <select
            v-model="selectedStatus"
            class="w-full pl-3 pr-8 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 appearance-none"
          >
            <option value="all">
              {{ t('SETTINGS.TEMPLATES.STATUS.ALL') }}
            </option>
            <option value="approved">
              {{ t('SETTINGS.TEMPLATES.STATUS.APPROVED') }}
            </option>
            <option value="pending">
              {{ t('SETTINGS.TEMPLATES.STATUS.PENDING_REVIEW') }}
            </option>
            <option value="rejected">
              {{ t('SETTINGS.TEMPLATES.STATUS.REJECTED') }}
            </option>
          </select>
        </div>
      </div>

      <!-- WhatsApp Inboxes -->
      <div v-if="whatsappInboxes.length > 0" class="mb-6">
        <h3 class="text-sm font-medium text-n-slate-12 mb-3">
          {{ t('SETTINGS.TEMPLATES.WHATSAPP.CHANNELS_TITLE') }}
        </h3>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div
            v-for="inbox in whatsappInboxes"
            :key="inbox.id"
            class="p-4 border border-n-weak rounded-lg bg-n-solid-2 hover:bg-n-solid-3 transition-colors cursor-pointer"
            :class="
              selectedInbox?.id === inbox.id
                ? 'ring-2 ring-n-blue-5 border-n-blue-5'
                : ''
            "
            @click="
              selectedInbox = selectedInbox?.id === inbox.id ? null : inbox
            "
          >
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <span class="i-logos-whatsapp size-4" />
                <h4 class="font-medium text-n-slate-12">{{ inbox.name }}</h4>
              </div>
              <span class="text-xs text-n-slate-11">{{ inbox.provider }}</span>
            </div>
            <p class="text-sm text-n-slate-11 mb-2">{{ inbox.phone_number }}</p>
            <div
              class="flex items-center justify-between text-xs text-n-slate-11"
            >
              <span>{{
                t('SETTINGS.TEMPLATES.WHATSAPP.TEMPLATES_COUNT', {
                  count: inbox.templates_count || 0,
                })
              }}</span>
              <span v-if="inbox.last_sync">
                {{ new Date(inbox.last_sync).toLocaleDateString() }}
              </span>
              <span v-else>{{
                t('SETTINGS.TEMPLATES.WHATSAPP.NEVER_SYNCED')
              }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="flex items-center gap-3 mb-6">
        <div class="relative w-48">
          <select
            v-model="selectedContent"
            class="w-full pl-3 pr-8 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 appearance-none"
          >
            <option
              v-for="option in contentFilterOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </div>

        <div class="relative w-48">
          <select
            v-model="selectedChannel"
            class="w-full pl-3 pr-8 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 appearance-none"
          >
            <option
              v-for="option in channelFilterOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </div>

        <div class="relative w-48">
          <select
            v-model="selectedLanguage"
            class="w-full pl-3 pr-8 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-blue-5 appearance-none"
          >
            <option
              v-for="option in languageFilterOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- Templates List -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <woot-loading-state :message="$t('SETTINGS.TEMPLATES.LOADING')" />
      </div>

      <div
        v-else-if="!filteredTemplates.length"
        class="flex items-center justify-center py-12 text-n-slate-11"
      >
        {{ t('SETTINGS.TEMPLATES.LIST.404') }}
      </div>

      <!-- Grouped view when "All" statuses selected -->
      <div v-else class="flex-1 space-y-6">
        <template v-if="selectedStatus === 'all'">
          <div
            v-for="group in ['approved', 'pending', 'rejected']"
            :key="group"
          >
            <div v-if="groupedByStatus[group]?.length" class="space-y-3">
              <div class="flex items-center gap-2">
                <span
                  class="text-xs font-semibold uppercase tracking-wide"
                  :class="getStatusColor(group)"
                >
                  {{ getStatusLabel(group) }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    t('SETTINGS.TEMPLATES.LIST.GROUP_COUNT', {
                      count: groupedByStatus[group].length,
                    })
                  }}
                </span>
              </div>
              <div class="space-y-3">
                <div
                  v-for="template in groupedByStatus[group]"
                  :key="template.id"
                  class="flex items-center justify-between p-4 border border-n-weak rounded-lg bg-n-solid-2 hover:bg-n-solid-3 transition-colors"
                >
                  <div class="flex items-center gap-4 flex-1">
                    <!-- Template Icon -->
                    <div
                      class="flex items-center justify-center w-8 h-8 bg-n-solid-3 rounded"
                    >
                      <span
                        :class="getTemplateIcon(template.category)"
                        class="size-4 text-n-slate-11"
                      />
                    </div>

                    <!-- Template Details -->
                    <div class="flex-1">
                      <div class="flex items-center gap-3 mb-1">
                        <h3 class="text-sm font-medium text-n-slate-12">
                          {{ template.name }}
                        </h3>
                        <span
                          class="text-xs font-medium"
                          :class="getStatusColor(template.status)"
                        >
                          {{
                            template.status.charAt(0).toUpperCase() +
                            template.status.slice(1)
                          }}
                        </span>
                      </div>
                      <div
                        class="flex items-center gap-4 text-sm text-n-slate-11"
                      >
                        <div class="flex items-center gap-1">
                          <span
                            :class="getTemplateIcon(template.category)"
                            class="size-3"
                          />
                          <span>{{ formatCategory(template.category) }}</span>
                        </div>
                        <div class="flex items-center gap-1">
                          <span class="i-lucide-globe size-3" />
                          <span>{{ template.language.toUpperCase() }}</span>
                        </div>
                        <div
                          v-if="template.inbox_name"
                          class="flex items-center gap-1"
                        >
                          <span class="i-lucide-inbox size-3" />
                          <span>{{ template.inbox_name }}</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Actions -->
                  <div class="flex items-center gap-1">
                    <Button
                      v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.VIEW')"
                      icon="i-lucide-eye"
                      slate
                      xs
                      faded
                      @click="viewTemplate(template)"
                    />
                    <Button
                      v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.EDIT')"
                      icon="i-lucide-pencil"
                      slate
                      xs
                      faded
                      @click="openEditPopup(template)"
                    />
                    <Button
                      v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.DELETE')"
                      icon="i-lucide-trash-2"
                      ruby
                      xs
                      faded
                      @click="openDelete(template)"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </template>

        <!-- Flat list for a specific status -->
        <template v-else>
          <div
            v-for="template in filteredTemplates"
            :key="template.id"
            class="flex items-center justify-between p-4 border border-n-weak rounded-lg bg-n-solid-2 hover:bg-n-solid-3 transition-colors"
          >
            <div class="flex items-center gap-4 flex-1">
              <!-- Template Icon -->
              <div
                class="flex items-center justify-center w-8 h-8 bg-n-solid-3 rounded"
              >
                <span
                  :class="getTemplateIcon(template.category)"
                  class="size-4 text-n-slate-11"
                />
              </div>

              <!-- Template Details -->
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-1">
                  <h3 class="text-sm font-medium text-n-slate-12">
                    {{ template.name }}
                  </h3>
                  <span
                    class="text-xs font-medium"
                    :class="getStatusColor(template.status)"
                  >
                    {{
                      template.status.charAt(0).toUpperCase() +
                      template.status.slice(1)
                    }}
                  </span>
                </div>
                <div class="flex items-center gap-4 text-sm text-n-slate-11">
                  <div class="flex items-center gap-1">
                    <span
                      :class="getTemplateIcon(template.category)"
                      class="size-3"
                    />
                    <span>{{ formatCategory(template.category) }}</span>
                  </div>
                  <div class="flex items-center gap-1">
                    <span class="i-lucide-globe size-3" />
                    <span>{{ template.language.toUpperCase() }}</span>
                  </div>
                  <div
                    v-if="template.inbox_name"
                    class="flex items-center gap-1"
                  >
                    <span class="i-lucide-inbox size-3" />
                    <span>{{ template.inbox_name }}</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Actions -->
            <div class="flex items-center gap-1">
              <Button
                v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.VIEW')"
                icon="i-lucide-eye"
                slate
                xs
                faded
                @click="viewTemplate(template)"
              />
              <Button
                v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.EDIT')"
                icon="i-lucide-pencil"
                slate
                xs
                faded
                @click="openEditPopup(template)"
              />
              <Button
                v-tooltip.top="t('SETTINGS.TEMPLATES.ACTIONS.DELETE')"
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDelete(template)"
              />
            </div>
          </div>
        </template>
      </div>

      <!-- Pagination Info and Controls -->
      <div
        v-if="totalEntries > 0"
        class="mt-6 flex items-center justify-between"
      >
        <div class="text-sm text-n-slate-11">
          {{
            t('SETTINGS.TEMPLATES.LIST.PAGINATION', {
              start: Math.min((currentPage - 1) * perPage + 1, totalEntries),
              end: Math.min(currentPage * perPage, totalEntries),
              total: totalEntries,
            })
          }}
        </div>

        <!-- Pagination Controls -->
        <div v-if="totalPages > 1" class="flex items-center gap-2">
          <Button
            icon="i-lucide-chevron-left"
            slate
            xs
            faded
            :disabled="currentPage === 1"
            @click="prevPage"
          />

          <!-- Page numbers -->
          <div class="flex items-center gap-1">
            <template v-for="page in pageNumbers" :key="page">
              <span v-if="page === '...'" class="text-n-slate-11 px-2">
                ...
              </span>
              <Button
                v-else
                :label="page.toString()"
                :class="page === currentPage ? 'bg-n-blue-5 text-white' : ''"
                slate
                xs
                faded
                @click="goToPage(page)"
              />
            </template>
          </div>

          <Button
            icon="i-lucide-chevron-right"
            slate
            xs
            faded
            :disabled="currentPage === totalPages"
            @click="nextPage"
          />
        </div>
      </div>
    </template>

    <!-- Confirm Delete Modal -->
    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="$t('SETTINGS.TEMPLATES.DELETE.CONFIRM.TITLE')"
      :message="
        selectedToDelete
          ? `${$t('SETTINGS.TEMPLATES.DELETE.CONFIRM.MESSAGE')} ${selectedToDelete.name}?`
          : ''
      "
      :confirm-text="$t('SETTINGS.TEMPLATES.DELETE.CONFIRM.YES')"
      :reject-text="$t('SETTINGS.TEMPLATES.DELETE.CONFIRM.NO')"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
    />
  </SettingsLayout>

  <!-- Inbox Selector Modal -->
  <woot-modal
    v-model:show="showInboxSelector"
    :on-close="() => (showInboxSelector = false)"
  >
    <div class="flex flex-col h-auto overflow-auto max-w-md w-full p-6">
      <h2 class="text-xl font-semibold text-n-slate-12 mb-4">
        {{ t('SETTINGS.TEMPLATES.WHATSAPP.SELECT_CHANNEL_TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 mb-4">
        {{ t('SETTINGS.TEMPLATES.WHATSAPP.SELECT_CHANNEL_DESC') }}
      </p>
      <div class="space-y-3 mb-6">
        <div
          v-for="inbox in whatsappInboxes"
          :key="inbox.id"
          class="p-3 border border-n-weak rounded-lg hover:bg-n-solid-2 cursor-pointer transition-colors"
          @click="
            () => {
              showInboxSelector.value = false;
              handleSyncTemplates(inbox.id);
            }
          "
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="i-logos-whatsapp size-4" />
              <div>
                <h4 class="font-medium text-n-slate-12">{{ inbox.name }}</h4>
                <p class="text-sm text-n-slate-11">
                  {{ inbox.phone_number }}
                </p>
              </div>
            </div>
            <div class="text-right text-xs text-n-slate-11">
              <div>
                {{
                  t('SETTINGS.TEMPLATES.WHATSAPP.TEMPLATES_COUNT', {
                    count: inbox.templates_count || 0,
                  })
                }}
              </div>
              <div v-if="inbox.last_sync">
                {{ new Date(inbox.last_sync).toLocaleDateString() }}
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="flex justify-end">
        <Button
          slate
          :label="t('SETTINGS.TEMPLATES.ACTIONS.CANCEL')"
          @click="showInboxSelector = false"
        />
      </div>
    </div>
  </woot-modal>

  <!-- Create Template Modal -->
  <woot-modal v-model:show="showCreatePopup" :on-close="hideCreatePopup">
    <CreateTemplate
      :inboxes="whatsappInboxes"
      :initial-inbox="selectedInbox"
      @close="hideCreatePopup"
      @created="onTemplateCreated"
    />
  </woot-modal>

  <!-- Edit Template Modal -->
  <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
    <CreateTemplate
      :inboxes="whatsappInboxes"
      :initial-inbox="selectedInbox"
      mode="edit"
      :template-to-edit="editingTemplate"
      @close="hideEditPopup"
      @created="onTemplateCreated"
    />
  </woot-modal>

  <!-- View Template Modal -->
  <woot-modal v-model:show="showViewModal" :on-close="closeViewModal">
    <div
      v-if="selectedTemplate"
      class="flex flex-col h-auto overflow-auto max-w-2xl w-full"
    >
      <woot-modal-header
        :header-title="
          t('SETTINGS.TEMPLATES.VIEW_MODAL.TITLE_PREFIX', {
            name: selectedTemplate.name,
          })
        "
        :header-content="t('SETTINGS.TEMPLATES.VIEW_MODAL.HEADER_CONTENT')"
      />

      <div class="flex flex-col w-full p-6 space-y-6">
        <!-- Template Info -->
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.TEMPLATE_NAME') }}
            </label>
            <p class="text-sm text-n-slate-11">{{ selectedTemplate.name }}</p>
          </div>
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.STATUS') }}
            </label>
            <span
              class="text-xs font-medium px-2 py-1 rounded"
              :class="getStatusColor(selectedTemplate.status)"
            >
              {{
                selectedTemplate.status.charAt(0).toUpperCase() +
                selectedTemplate.status.slice(1)
              }}
            </span>
          </div>
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.CATEGORY') }}
            </label>
            <p class="text-sm text-n-slate-11">
              {{ formatCategory(selectedTemplate.category) }}
            </p>
          </div>
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.LANGUAGE') }}
            </label>
            <p class="text-sm text-n-slate-11">
              {{ selectedTemplate.language.toUpperCase() }}
            </p>
          </div>
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.CHANNEL') }}
            </label>
            <p class="text-sm text-n-slate-11">
              {{ selectedTemplate.inbox_name }}
            </p>
          </div>
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.FIELDS.CONTENT_TYPE') }}
            </label>
            <p class="text-sm text-n-slate-11">
              {{ selectedTemplate.content_type || 'text' }}
            </p>
          </div>
        </div>

        <!-- Template Components -->
        <div
          v-if="
            selectedTemplate.components && selectedTemplate.components.length
          "
        >
          <label class="block text-sm font-medium text-n-slate-12 mb-3">
            {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.COMPONENTS_TITLE') }}
          </label>
          <div class="space-y-4">
            <div
              v-for="(component, index) in selectedTemplate.components"
              :key="index"
              class="p-4 border border-n-weak rounded-lg bg-n-solid-1"
            >
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-medium text-n-blue-text">
                  {{ component.type }}
                </span>
                <span v-if="component.format" class="text-xs text-n-slate-9">
                  {{ component.format }}
                </span>
              </div>
              <p
                v-if="component.text"
                class="text-sm text-n-slate-12 whitespace-pre-wrap"
              >
                {{ component.text }}
              </p>

              <!-- Buttons in component -->
              <div
                v-if="component.buttons && component.buttons.length"
                class="mt-3"
              >
                <label class="block text-xs font-medium text-n-slate-11 mb-2">
                  {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.BUTTONS_LABEL') }}
                </label>
                <div class="flex flex-wrap gap-2">
                  <span
                    v-for="(button, btnIndex) in component.buttons"
                    :key="btnIndex"
                    class="px-3 py-1 text-xs bg-n-solid-3 rounded border border-n-weak"
                  >
                    {{ button.text }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Raw Content fallback -->
        <div v-else-if="selectedTemplate.content">
          <label class="block text-sm font-medium text-n-slate-12 mb-2">
            {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.RAW_CONTENT_TITLE') }}
          </label>
          <div class="p-4 border border-n-weak rounded-lg bg-n-solid-1">
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
              {{ selectedTemplate.content }}
            </p>
          </div>
        </div>

        <!-- Template Metadata -->
        <div
          v-if="
            selectedTemplate.meta && Object.keys(selectedTemplate.meta).length
          "
        >
          <label class="block text-sm font-medium text-n-slate-12 mb-2">
            {{ t('SETTINGS.TEMPLATES.VIEW_MODAL.ADDITIONAL_INFO_TITLE') }}
          </label>
          <div class="p-4 border border-n-weak rounded-lg bg-n-solid-1">
            <pre class="text-xs text-n-slate-11 overflow-auto">{{
              JSON.stringify(selectedTemplate.meta, null, 2)
            }}</pre>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="flex justify-end w-full pt-4">
          <Button
            slate
            :label="t('SETTINGS.TEMPLATES.VIEW_MODAL.CLOSE')"
            @click="closeViewModal"
          />
        </div>
      </div>
    </div>
  </woot-modal>
</template>
