<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import StorageAPI from 'dashboard/api/storage';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();
const cleanupConfirmDialog = ref(null);
const deduplicateConfirmDialog = ref(null);

const analyzing = ref(false);
const cleanupLoading = ref(false);
const deduplicateLoading = ref(false);
const showDuplicates = ref(false);
const duplicatesLoading = ref(false);
const showLargestFiles = ref(false);
const largestFilesLoading = ref(false);

const storageData = ref(null);
const duplicatesList = ref([]);
const largestFilesList = ref([]);

const hasData = computed(() => storageData.value !== null);

const formatBytes = bytes => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / k ** i).toFixed(2))} ${sizes[i]}`;
};

const totalSize = computed(() => {
  if (!storageData.value) return 0;
  return storageData.value.overview?.total_size || 0;
});

const orphanSize = computed(() => {
  if (!storageData.value) return 0;
  return storageData.value.orphan_blobs?.size || 0;
});

const duplicateWasted = computed(() => {
  if (!storageData.value) return 0;
  return storageData.value.duplicates?.wasted_space || 0;
});

const potentialSavings = computed(() => {
  return orphanSize.value + duplicateWasted.value;
});

const cleanupConfirmMessage = computed(() => {
  if (!storageData.value) return '';
  return t('STORAGE_MGMT.CLEANUP_CONFIRM', {
    count: storageData.value.orphan_blobs?.count || 0,
    size: formatBytes(orphanSize.value),
  });
});

const deduplicateConfirmMessage = computed(() => {
  if (!storageData.value) return '';
  return t('STORAGE_MGMT.DEDUPLICATE_CONFIRM', {
    count: storageData.value.duplicates?.files || 0,
    size: formatBytes(duplicateWasted.value),
  });
});

const formatNumber = num => {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
};

const analyzeStorage = async () => {
  try {
    analyzing.value = true;
    const response = await StorageAPI.analyze();
    storageData.value = response.data;
    useAlert(t('STORAGE_MGMT.ANALYZE_SUCCESS'));
  } catch (error) {
    useAlert(t('STORAGE_MGMT.ANALYZE_ERROR'));
  } finally {
    analyzing.value = false;
  }
};

const loadDuplicates = async () => {
  try {
    duplicatesLoading.value = true;
    showDuplicates.value = true;
    const response = await StorageAPI.duplicates(50);
    duplicatesList.value = response.data.duplicates || [];
  } catch (error) {
    useAlert(t('STORAGE_MGMT.DUPLICATES_ERROR'));
  } finally {
    duplicatesLoading.value = false;
  }
};

const loadLargestFiles = async () => {
  try {
    largestFilesLoading.value = true;
    showLargestFiles.value = true;
    const response = await StorageAPI.largestFiles(20);
    largestFilesList.value = response.data.files || [];
  } catch (error) {
    useAlert(t('STORAGE_MGMT.LARGEST_FILES_ERROR'));
  } finally {
    largestFilesLoading.value = false;
  }
};

const getSourceLabel = key => {
  const sourceLabels = {
    messages: 'STORAGE_MGMT.SOURCE_MESSAGES',
    canned_responses: 'STORAGE_MGMT.SOURCE_CANNED_RESPONSES',
  };
  return sourceLabels[key] || 'STORAGE_MGMT.SOURCE_DEFAULT';
};

const formatDate = dateString => {
  const date = new Date(dateString);
  return date.toLocaleDateString();
};

const cleanupOrphans = async () => {
  const confirmed = await cleanupConfirmDialog.value.showConfirmation();

  if (!confirmed) {
    return;
  }

  try {
    cleanupLoading.value = true;
    const response = await StorageAPI.cleanupOrphans();
    useAlert(
      t('STORAGE_MGMT.CLEANUP_SUCCESS', {
        count: response.data.cleaned_count,
        size: formatBytes(response.data.space_freed),
      })
    );
    await analyzeStorage();
  } catch (error) {
    useAlert(t('STORAGE_MGMT.CLEANUP_ERROR'));
  } finally {
    cleanupLoading.value = false;
  }
};

const deduplicateFiles = async () => {
  const confirmed = await deduplicateConfirmDialog.value.showConfirmation();

  if (!confirmed) {
    return;
  }

  try {
    deduplicateLoading.value = true;
    const response = await StorageAPI.deduplicate();
    useAlert(
      t('STORAGE_MGMT.DEDUPLICATE_SUCCESS', {
        count: response.data.deduplicated_count,
        size: formatBytes(response.data.space_saved),
      })
    );
    await analyzeStorage();
    if (showDuplicates.value) {
      await loadDuplicates();
    }
  } catch (error) {
    useAlert(t('STORAGE_MGMT.DEDUPLICATE_ERROR'));
  } finally {
    deduplicateLoading.value = false;
  }
};

onMounted(() => {
  analyzeStorage();
});
</script>

<template>
  <SettingsLayout :is-loading="analyzing && !hasData" :no-records-found="false">
    <template #header>
      <BaseSettingsHeader
        :title="$t('STORAGE_MGMT.TITLE')"
        :description="$t('STORAGE_MGMT.DESCRIPTION')"
      >
        <template #actions>
          <NextButton
            :disabled="analyzing"
            size="small"
            blue
            @click="analyzeStorage"
          >
            <span v-if="!analyzing">{{ $t('STORAGE_MGMT.REFRESH') }}</span>
            <Spinner v-else size="small" />
          </NextButton>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div v-if="hasData" class="flex flex-col gap-6">
        <!-- Storage Overview Box -->
        <div
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.OVERVIEW_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ $t('STORAGE_MGMT.OVERVIEW_SUBTITLE') }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
              <!-- Total Storage -->
              <div class="rounded-md border border-n-weak bg-n-solid-1 p-4">
                <div class="text-sm font-medium text-n-slate-11">
                  {{ $t('STORAGE_MGMT.TOTAL_STORAGE') }}
                </div>
                <div class="mt-2 text-2xl font-bold text-n-slate-12">
                  {{ formatBytes(totalSize) }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{
                    $t('STORAGE_MGMT.TOTAL_FILES', {
                      count: formatNumber(storageData.overview.total_blobs),
                    })
                  }}
                </div>
              </div>

              <!-- Orphan Files -->
              <div class="rounded-md border border-n-weak bg-n-solid-1 p-4">
                <div class="text-sm font-medium text-n-yellow-11">
                  {{ $t('STORAGE_MGMT.ORPHAN_FILES') }}
                </div>
                <div class="mt-2 text-2xl font-bold text-n-yellow-12">
                  {{ formatBytes(orphanSize) }}
                </div>
                <div class="mt-1 text-xs text-n-yellow-11">
                  {{
                    $t('STORAGE_MGMT.ORPHAN_COUNT', {
                      count: formatNumber(storageData.orphan_blobs.count),
                    })
                  }}
                </div>
              </div>

              <!-- Duplicate Waste -->
              <div class="rounded-md border border-n-weak bg-n-solid-1 p-4">
                <div class="text-sm font-medium text-n-ruby-11">
                  {{ $t('STORAGE_MGMT.DUPLICATE_WASTE') }}
                </div>
                <div class="mt-2 text-2xl font-bold text-n-ruby-12">
                  {{ formatBytes(duplicateWasted) }}
                </div>
                <div class="mt-1 text-xs text-n-ruby-11">
                  {{
                    $t('STORAGE_MGMT.DUPLICATE_COUNT', {
                      count: formatNumber(storageData.duplicates.files),
                    })
                  }}
                </div>
              </div>
            </div>

            <!-- Potential Savings -->
            <div
              v-if="potentialSavings > 0"
              class="mt-4 rounded-md border border-n-weak bg-n-solid-1 p-4"
            >
              <div class="flex items-center justify-between">
                <div>
                  <div class="text-sm font-medium text-n-green-11">
                    {{ $t('STORAGE_MGMT.POTENTIAL_SAVINGS') }}
                  </div>
                  <div class="mt-1 text-xl font-bold text-n-green-12">
                    {{ formatBytes(potentialSavings) }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Storage by Source Box -->
        <div
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.BY_SOURCE_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ $t('STORAGE_MGMT.BY_SOURCE_SUBTITLE') }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="space-y-3">
              <div
                v-for="(source, key) in storageData.by_source"
                :key="key"
                class="flex items-center justify-between rounded-md border border-n-weak bg-n-solid-1 p-3"
              >
                <div class="flex items-center gap-3">
                  <span
                    class="flex items-center justify-center w-8 h-8 rounded-md bg-n-alpha-2 text-n-slate-11"
                  >
                    <span
                      class="w-4 h-4"
                      :class="
                        key === 'messages'
                          ? 'i-lucide-message-square'
                          : key === 'canned_responses'
                            ? 'i-lucide-bookmark'
                            : 'i-lucide-file'
                      "
                    />
                  </span>
                  <div>
                    <div class="text-sm font-medium text-n-slate-12">
                      {{ $t(getSourceLabel(key)) }}
                    </div>
                    <div class="text-xs text-n-slate-11">
                      {{ formatNumber(source.count) }}
                      {{ $t('STORAGE_MGMT.FILES_LABEL') }}
                    </div>
                  </div>
                </div>
                <div class="text-sm font-semibold text-n-slate-12">
                  {{ formatBytes(source.size) }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Storage by Content Type Box -->
        <div
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.BY_TYPE_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ $t('STORAGE_MGMT.BY_TYPE_SUBTITLE') }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="space-y-2">
              <div
                v-for="item in storageData.by_content_type.slice(0, 10)"
                :key="item.content_type"
                class="flex items-center justify-between rounded border border-n-weak bg-n-solid-1 p-2"
              >
                <div class="flex items-center gap-2">
                  <span class="text-xs text-n-slate-11">
                    {{
                      $t('STORAGE_MGMT.CONTENT_TYPE_COUNT', {
                        type: item.content_type,
                        count: formatNumber(item.count),
                      })
                    }}
                  </span>
                </div>
                <span class="text-sm font-medium text-n-slate-12">
                  {{ formatBytes(item.size) }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Actions Box -->
        <div
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.ACTIONS_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ $t('STORAGE_MGMT.ACTIONS_SUBTITLE') }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="space-y-4">
              <!-- Cleanup Orphans -->
              <div
                class="flex items-center justify-between rounded-md border border-n-weak bg-n-solid-1 p-4"
              >
                <div class="flex-1">
                  <h4 class="text-sm font-semibold text-n-yellow-12">
                    {{ $t('STORAGE_MGMT.CLEANUP_ORPHANS_TITLE') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-yellow-11">
                    {{ $t('STORAGE_MGMT.CLEANUP_ORPHANS_DESC') }}
                  </p>
                </div>
                <NextButton
                  :disabled="
                    cleanupLoading ||
                    !storageData.orphan_blobs.count ||
                    storageData.orphan_blobs.count === 0
                  "
                  size="small"
                  amber
                  @click="cleanupOrphans"
                >
                  <span v-if="!cleanupLoading">
                    {{ $t('STORAGE_MGMT.CLEANUP_ACTION') }}
                  </span>
                  <Spinner v-else size="small" />
                </NextButton>
              </div>

              <!-- View Duplicates -->
              <div
                class="flex items-center justify-between rounded-md border border-n-weak bg-n-solid-1 p-4"
              >
                <div class="flex-1">
                  <h4 class="text-sm font-semibold text-n-iris-12">
                    {{ $t('STORAGE_MGMT.VIEW_DUPLICATES_TITLE') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-iris-11">
                    {{ $t('STORAGE_MGMT.VIEW_DUPLICATES_DESC') }}
                  </p>
                </div>
                <NextButton
                  :disabled="
                    duplicatesLoading ||
                    !storageData.duplicates.files ||
                    storageData.duplicates.files === 0
                  "
                  size="small"
                  slate
                  @click="loadDuplicates"
                >
                  <span v-if="!duplicatesLoading">
                    {{ $t('STORAGE_MGMT.VIEW_ACTION') }}
                  </span>
                  <Spinner v-else size="small" />
                </NextButton>
              </div>

              <!-- View Largest Files -->
              <div
                class="flex items-center justify-between rounded-md border border-n-weak bg-n-solid-1 p-4"
              >
                <div class="flex-1">
                  <h4 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('STORAGE_MGMT.LARGEST_FILES_TITLE') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-slate-11">
                    {{ $t('STORAGE_MGMT.LARGEST_FILES_SUBTITLE') }}
                  </p>
                </div>
                <NextButton
                  :disabled="largestFilesLoading"
                  size="small"
                  slate
                  @click="loadLargestFiles"
                >
                  <span v-if="!largestFilesLoading">
                    {{ $t('STORAGE_MGMT.LARGEST_FILES_ACTION') }}
                  </span>
                  <Spinner v-else size="small" />
                </NextButton>
              </div>

              <!-- Deduplicate -->
              <div
                class="flex items-center justify-between rounded-md border border-n-weak bg-n-solid-1 p-4"
              >
                <div class="flex-1">
                  <h4 class="text-sm font-semibold text-n-ruby-12">
                    {{ $t('STORAGE_MGMT.DEDUPLICATE_TITLE') }}
                  </h4>
                  <p class="mt-1 text-xs text-n-ruby-11">
                    {{ $t('STORAGE_MGMT.DEDUPLICATE_DESC') }}
                  </p>
                </div>
                <NextButton
                  :disabled="
                    deduplicateLoading ||
                    !storageData.duplicates.files ||
                    storageData.duplicates.files === 0
                  "
                  size="small"
                  ruby
                  @click="deduplicateFiles"
                >
                  <span v-if="!deduplicateLoading">
                    {{ $t('STORAGE_MGMT.DEDUPLICATE_ACTION') }}
                  </span>
                  <Spinner v-else size="small" />
                </NextButton>
              </div>
            </div>
          </div>
        </div>

        <!-- Duplicates List Box -->
        <div
          v-if="showDuplicates && duplicatesList.length > 0"
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.DUPLICATES_LIST_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{
                $t('STORAGE_MGMT.DUPLICATES_LIST_SUBTITLE', {
                  count: duplicatesList.length,
                })
              }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="space-y-2">
              <div
                v-for="(dup, index) in duplicatesList"
                :key="index"
                class="flex items-center justify-between rounded border border-n-weak bg-n-solid-1 p-3"
              >
                <div class="flex-1">
                  <div class="text-sm font-medium text-n-slate-12">
                    {{ dup.filename }}
                  </div>
                  <div
                    class="mt-1 flex items-center gap-3 text-xs text-n-slate-11"
                  >
                    <span>{{ dup.content_type }}</span>
                    <span>{{ $t('STORAGE_MGMT.SEPARATOR') }}</span>
                    <span>{{ dup.count }} {{ $t('STORAGE_MGMT.COPIES') }}</span>
                    <span>{{ $t('STORAGE_MGMT.SEPARATOR') }}</span>
                    <!-- eslint-disable-next-line prettier/prettier -->
                    <span>{{ formatBytes(dup.total_size) }} {{ $t('STORAGE_MGMT.TOTAL') }}</span>
                  </div>
                </div>
                <div class="text-sm font-semibold text-n-ruby-11">
                  {{ formatBytes(dup.wasted_space) }}
                  {{ $t('STORAGE_MGMT.WASTED') }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Largest Files List Box -->
        <div
          v-if="showLargestFiles && largestFilesList.length > 0"
          class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
        >
          <div class="flex flex-col gap-2 items-start px-5 py-4">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ $t('STORAGE_MGMT.LARGEST_FILES_TITLE') }}
            </h3>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ $t('STORAGE_MGMT.LARGEST_FILES_SUBTITLE') }}
            </p>
          </div>

          <div class="px-5 py-4">
            <div class="space-y-2">
              <div
                v-for="(file, index) in largestFilesList"
                :key="index"
                class="flex items-center justify-between rounded border border-n-weak bg-n-solid-1 p-3"
              >
                <div class="flex-1">
                  <div class="flex items-center gap-2">
                    <div class="text-sm font-medium text-n-slate-12">
                      {{ file.filename }}
                    </div>
                    <span
                      v-if="file.is_duplicate"
                      class="rounded bg-n-ruby-3 px-2 py-0.5 text-xs text-n-ruby-11"
                    >
                      {{
                        $t('STORAGE_MGMT.FILE_IS_DUPLICATE', {
                          count: file.duplicate_count,
                        })
                      }}
                    </span>
                  </div>
                  <div
                    class="mt-1 flex items-center gap-3 text-xs text-n-slate-11"
                  >
                    <span>{{ file.content_type }}</span>
                    <span>{{ $t('STORAGE_MGMT.SEPARATOR') }}</span>
                    <!-- eslint-disable-next-line prettier/prettier -->
                    <span>{{ $t('STORAGE_MGMT.FILE_CREATED') }} {{ formatDate(file.created_at) }}</span>
                  </div>
                </div>
                <div class="text-sm font-semibold text-n-slate-12">
                  {{ formatBytes(file.size) }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>

    <woot-confirm-modal
      ref="cleanupConfirmDialog"
      :title="$t('STORAGE_MGMT.CLEANUP_ORPHANS_TITLE')"
      :description="cleanupConfirmMessage"
    />
    <woot-confirm-modal
      ref="deduplicateConfirmDialog"
      :title="$t('STORAGE_MGMT.DEDUPLICATE_TITLE')"
      :description="deduplicateConfirmMessage"
    />
  </SettingsLayout>
</template>
