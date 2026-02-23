<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
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

// Estado del análisis
const analysisStatus = ref('not_started'); // 'not_started', 'in_progress', 'completed', 'timeout', 'failed'
const analysisError = ref(null);
let statusCheckInterval = null;

// Estado de deduplicación
const deduplicationStatus = ref('not_started');
let deduplicationStatusCheckInterval = null;

// Estado de limpieza
const cleanupStatus = ref('not_started');
let cleanupStatusCheckInterval = null;

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

const lastAnalyzedAt = computed(() => {
  if (!storageData.value?.analyzed_at) return null;
  return new Date(storageData.value.analyzed_at);
});

const lastAnalyzedFormatted = computed(() => {
  if (!lastAnalyzedAt.value) return '';
  
  const now = new Date();
  const diffMs = now - lastAnalyzedAt.value;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  
  if (diffMins < 1) return t('STORAGE_MGMT.JUST_NOW');
  if (diffMins < 60) return t('STORAGE_MGMT.MINUTES_AGO', { minutes: diffMins });
  if (diffHours < 2) return t('STORAGE_MGMT.HOURS_AGO', { hours: diffHours });
  
  return lastAnalyzedAt.value.toLocaleString();
});

const analysisIsStale = computed(() => {
  if (!lastAnalyzedAt.value) return false;
  const now = new Date();
  const diffHours = (now - lastAnalyzedAt.value) / 3600000;
  return diffHours > 1.5; // Considerar viejo después de 1.5 horas
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

// Verificar el estado del análisis
const checkAnalysisStatus = async (showAlert = false) => {
  try {
    const response = await StorageAPI.status();
    const { status, result, error } = response.data;

    analysisStatus.value = status;
    analysisError.value = error || null;

    if (status === 'completed' && result) {
      storageData.value = result;
      stopPolling();
      analyzing.value = false;
      if (showAlert) {
        useAlert(t('STORAGE_MGMT.ANALYZE_SUCCESS'));
      }
    } else if (status === 'in_progress') {
      // Continuar polling si está en progreso
      analyzing.value = true;
      if (!statusCheckInterval) {
        startPolling();
      }
    } else if (status === 'timeout' || status === 'failed') {
      stopPolling();
      analyzing.value = false;
      if (showAlert) {
        useAlert(error || t('STORAGE_MGMT.ANALYZE_ERROR'));
      }
    } else if (status === 'not_started') {
      // No hay análisis previo
      analyzing.value = false;
      stopPolling();
    }
  } catch (error) {
    console.error('Error checking analysis status:', error);
    analyzing.value = false;
  }
};

// Iniciar polling para verificar el estado
const startPolling = () => {
  if (statusCheckInterval) return;
  
  statusCheckInterval = setInterval(() => {
    checkAnalysisStatus(false);
  }, 3000); // Verificar cada 3 segundos
};

// Detener polling
const stopPolling = () => {
  if (statusCheckInterval) {
    clearInterval(statusCheckInterval);
    statusCheckInterval = null;
  }
};

const analyzeStorage = async () => {
  try {
    analyzing.value = true;
    analysisStatus.value = 'in_progress';
    const response = await StorageAPI.analyze();
    
    // Si se puso en cola, iniciar polling
    if (response.data.status === 'queued' || response.data.status === 'in_progress') {
      useAlert(t('STORAGE_MGMT.ANALYZE_QUEUED'));
      startPolling();
    } else if (response.data.overview) {
      // Análisis síncrono completado
      storageData.value = response.data;
      analysisStatus.value = 'completed';
      useAlert(t('STORAGE_MGMT.ANALYZE_SUCCESS'));
    }
  } catch (error) {
    analysisStatus.value = 'failed';
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
    cleanupStatus.value = 'in_progress';
    await StorageAPI.cleanupOrphans();
    useAlert(t('STORAGE_MGMT.CLEANUP_QUEUED'));
    startCleanupPolling();
  } catch (error) {
    useAlert(t('STORAGE_MGMT.CLEANUP_ERROR'));
    cleanupLoading.value = false;
    cleanupStatus.value = 'failed';
  }
};

// Check cleanup status
const checkCleanupStatus = async (showAlert = true) => {
  try {
    const response = await StorageAPI.cleanupStatus();
    const { status } = response.data;

    cleanupStatus.value = status;

    if (status === 'completed') {
      stopCleanupPolling();
      cleanupLoading.value = false;
      if (showAlert) {
        useAlert(
          t('STORAGE_MGMT.CLEANUP_SUCCESS', {
            count: response.data.cleaned_count,
            size: formatBytes(response.data.space_freed),
          })
        );
      }
      await analyzeStorage();
    } else if (status === 'in_progress') {
      cleanupLoading.value = true;
      if (!cleanupStatusCheckInterval) {
        startCleanupPolling();
      }
    } else if (status === 'interrupted') {
      stopCleanupPolling();
      cleanupLoading.value = false;
      if (showAlert) {
        useAlert(t('STORAGE_MGMT.CLEANUP_INTERRUPTED'));
      }
    } else if (status === 'error') {
      stopCleanupPolling();
      cleanupLoading.value = false;
      if (showAlert) {
        useAlert(t('STORAGE_MGMT.CLEANUP_ERROR'));
      }
    } else if (status === 'not_started') {
      cleanupLoading.value = false;
      stopCleanupPolling();
    }
  } catch (error) {
    console.error('Error checking cleanup status:', error);
    cleanupLoading.value = false;
  }
};

// Start cleanup polling
const startCleanupPolling = () => {
  if (cleanupStatusCheckInterval) return;
  
  cleanupStatusCheckInterval = setInterval(() => {
    checkCleanupStatus(false);
  }, 3000);
};

// Stop cleanup polling
const stopCleanupPolling = () => {
  if (cleanupStatusCheckInterval) {
    clearInterval(cleanupStatusCheckInterval);
    cleanupStatusCheckInterval = null;
  }
};

const deduplicateFiles = async () => {
  const confirmed = await deduplicateConfirmDialog.value.showConfirmation();

  if (!confirmed) {
    return;
  }

  try {
    deduplicateLoading.value = true;
    deduplicationStatus.value = 'in_progress';
    await StorageAPI.deduplicate();
    useAlert(t('STORAGE_MGMT.DEDUPLICATE_QUEUED'));
    startDeduplicationPolling();
  } catch (error) {
    useAlert(t('STORAGE_MGMT.DEDUPLICATE_ERROR'));
    deduplicateLoading.value = false;
    deduplicationStatus.value = 'failed';
  }
};

// Check deduplication status
const checkDeduplicationStatus = async (showAlert = true) => {
  try {
    const response = await StorageAPI.deduplicationStatus();
    const { status } = response.data;

    deduplicationStatus.value = status;

    if (status === 'completed') {
      stopDeduplicationPolling();
      deduplicateLoading.value = false;
      if (showAlert) {
        useAlert(
          t('STORAGE_MGMT.DEDUPLICATE_SUCCESS', {
            count: response.data.deduplicated_count,
            size: formatBytes(response.data.space_saved),
          })
        );
      }
      await analyzeStorage();
      if (showDuplicates.value) {
        await loadDuplicates();
      }
    } else if (status === 'in_progress') {
      deduplicateLoading.value = true;
      if (!deduplicationStatusCheckInterval) {
        startDeduplicationPolling();
      }
    } else if (status === 'interrupted') {
      stopDeduplicationPolling();
      deduplicateLoading.value = false;
      if (showAlert) {
        useAlert(t('STORAGE_MGMT.DEDUPLICATE_INTERRUPTED'));
      }
    } else if (status === 'error') {
      stopDeduplicationPolling();
      deduplicateLoading.value = false;
      if (showAlert) {
        useAlert(t('STORAGE_MGMT.DEDUPLICATE_ERROR'));
      }
    } else if (status === 'not_started') {
      deduplicateLoading.value = false;
      stopDeduplicationPolling();
    }
  } catch (error) {
    console.error('Error checking deduplication status:', error);
    deduplicateLoading.value = false;
  }
};

// Start deduplication polling
const startDeduplicationPolling = () => {
  if (deduplicationStatusCheckInterval) return;
  
  deduplicationStatusCheckInterval = setInterval(() => {
    checkDeduplicationStatus(false);
  }, 3000);
};

// Stop deduplication polling
const stopDeduplicationPolling = () => {
  if (deduplicationStatusCheckInterval) {
    clearInterval(deduplicationStatusCheckInterval);
    deduplicationStatusCheckInterval = null;
  }
};

onMounted(() => {
  // NO iniciar análisis automáticamente, solo verificar el estado
  checkAnalysisStatus(false);
});

onUnmounted(() => {
  stopPolling();
  stopCleanupPolling();
  stopDeduplicationPolling();
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
      <!-- Info del último análisis -->
      <div
        v-if="hasData && lastAnalyzedAt"
        class="mb-4 rounded-md border bg-n-solid-1 p-3"
        :class="analysisIsStale ? 'border-n-amber-6 bg-n-amber-2' : 'border-n-weak'"
      >
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span
              class="flex items-center justify-center w-6 h-6 rounded-full"
              :class="analysisIsStale ? 'bg-n-amber-3 text-n-amber-11' : 'bg-n-green-3 text-n-green-11'"
            >
              <span class="w-4 h-4" :class="analysisIsStale ? 'i-lucide-clock' : 'i-lucide-check-circle'" />
            </span>
            <div>
              <span class="text-sm font-medium" :class="analysisIsStale ? 'text-n-amber-11' : 'text-n-slate-12'">
                {{ $t('STORAGE_MGMT.LAST_ANALYZED') }}: {{ lastAnalyzedFormatted }}
              </span>
              <span v-if="analysisIsStale" class="ml-2 text-xs text-n-amber-10">
                {{ $t('STORAGE_MGMT.DATA_MAY_BE_OUTDATED') }}
              </span>
            </div>
          </div>
          <span v-if="storageData.analysis_duration_seconds" class="text-xs text-n-slate-11">
            {{ $t('STORAGE_MGMT.ANALYSIS_TOOK', { seconds: storageData.analysis_duration_seconds.toFixed(1) }) }}
          </span>
        </div>
      </div>

      <!-- Estado del Análisis -->
      <div
        v-if="analysisStatus === 'in_progress'"
        class="mb-6 rounded-md border border-n-iris-6 bg-n-iris-2 p-4"
      >
        <div class="flex items-center gap-3">
          <Spinner size="small" />
          <div>
            <div class="text-sm font-medium text-n-iris-11">
              {{ $t('STORAGE_MGMT.ANALYSIS_IN_PROGRESS') }}
            </div>
            <div class="text-xs text-n-iris-10 mt-1">
              {{ $t('STORAGE_MGMT.ANALYSIS_IN_PROGRESS_DESC') }}
            </div>
          </div>
        </div>
      </div>

      <!-- No hay datos -->
      <div
        v-if="!hasData && analysisStatus === 'not_started'"
        class="mb-6 rounded-md border border-n-weak bg-n-solid-1 p-6 text-center"
      >
        <div class="text-n-slate-11">
          <div class="text-base font-medium text-n-slate-12 mb-2">
            {{ $t('STORAGE_MGMT.NO_DATA_TITLE') }}
          </div>
          <div class="text-sm">
            {{ $t('STORAGE_MGMT.NO_DATA_DESC') }}
          </div>
          <NextButton class="mt-4" size="small" blue @click="analyzeStorage">
            {{ $t('STORAGE_MGMT.START_ANALYSIS') }}
          </NextButton>
        </div>
      </div>

      <!-- Error en el análisis -->
      <div
        v-if="analysisStatus === 'failed' || analysisStatus === 'timeout'"
        class="mb-6 rounded-md border border-n-ruby-6 bg-n-ruby-2 p-4"
      >
        <div class="text-sm font-medium text-n-ruby-11 mb-1">
          {{ $t('STORAGE_MGMT.ANALYSIS_ERROR_TITLE') }}
        </div>
        <div class="text-xs text-n-ruby-10">
          {{ analysisError || $t('STORAGE_MGMT.ANALYZE_ERROR') }}
        </div>
      </div>

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
