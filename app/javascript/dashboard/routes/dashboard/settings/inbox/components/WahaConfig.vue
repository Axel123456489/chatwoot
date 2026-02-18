<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WahaSessionsAPI from 'dashboard/api/wahaSessions';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'shared/components/Spinner.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const loading = ref(false);
const qrCode = ref('');
const qrCodeKey = ref(0);
const status = ref('');
const phoneNumber = ref('');
const presence = ref('');
const refreshTimer = ref(null);
const isPolling = ref(false);
const lastStatusCheckAt = ref(0);
const expiresIn = ref(10);
const localWahaData = ref({});

const TICK_INTERVAL_MS = 1000;
const STATUS_POLL_MS = 5000;

// Advanced config - form state
const advancedConfig = ref({
  debug: false,
  metadata: {},
  ignore_groups: false,
  ignore_channels: true,
  ignore_status: true,
  ignore_broadcast: true,
  proxy_server: '',
  proxy_username: '',
  proxy_password: '',
  noweb_store_enabled: true,
  noweb_store_full_sync: false,
});

const metadataString = ref('');
const savingConfig = ref(false);

const emDash = '—'; // For use as fallback value

const wahaSession = computed(() => props.inbox.waha_session);
const sessionId = computed(() => wahaSession.value?.id);
const sessionName = computed(() => wahaSession.value?.session_name || '');
const inboxIdentifier = computed(() => props.inbox.inbox_identifier);
const webhookUrl = computed(() => props.inbox.channel?.webhook_url || '');
const channelId = computed(() => props.inbox.channel_id);
const appInfo = computed(() => {
  const data = {
    ...(wahaSession.value?.waha_data || {}),
    ...localWahaData.value,
  };
  const app = data.app || {};
  const baseSession = sessionName.value;
  const computedAppId = baseSession ? `chatwoot_${baseSession}` : '';

  return {
    appId: app.id || data.app_id || computedAppId,
    session: app.session || baseSession,
    remoteStatus: data.status || status.value,
    engine: data.engine?.engine,
    url: app.config?.url,
    locale: app.config?.locale,
    linkPreview: app.config?.linkPreview,
    enabled: app.enabled,
    accountId: app.config?.accountId,
    inboxId: app.config?.inboxId,
    inboxIdentifier: app.config?.inboxIdentifier || inboxIdentifier.value,
    webhook: data.webhook_url,
  };
});

const statusColor = computed(() => {
  switch (status.value) {
    case 'connected':
      return 'text-green-700';
    case 'scan_qr':
    case 'connecting':
    case 'starting':
      return 'text-amber-600';
    case 'failed':
    case 'stopped':
      return 'text-red-600';
    default:
      return 'text-slate-600';
  }
});

const statusText = computed(() => {
  const statusMap = {
    connected: t('INBOX_MGMT.ADD.WAHA.STATUS.CONNECTED'),
    scan_qr: t('INBOX_MGMT.ADD.WAHA.STATUS.SCAN_QR'),
    connecting: t('INBOX_MGMT.ADD.WAHA.STATUS.CONNECTING'),
    starting: t('INBOX_MGMT.ADD.WAHA.STATUS.STARTING'),
    failed: t('INBOX_MGMT.ADD.WAHA.STATUS.FAILED'),
    stopped: t('INBOX_MGMT.ADD.WAHA.STATUS.STOPPED'),
    pending: t('INBOX_MGMT.ADD.WAHA.STATUS.PENDING'),
  };
  return statusMap[status.value] || statusMap.pending;
});

const needsQRCode = computed(() => {
  return ['scan_qr', 'starting', 'pending'].includes(status.value);
});

const qrCodeSrc = computed(() => {
  return qrCode.value ? `${qrCode.value}#${qrCodeKey.value}` : '';
});

const loadAdvancedConfig = async () => {
  if (!sessionId.value) return;

  try {
    // Load config from WAHA (source of truth)
    const response = await WahaSessionsAPI.syncConfig(sessionId.value);
    const wahaConfig = response.data.waha_config || {};
    const session = response.data.session;

    // Update local session data
    if (session) {
      Object.assign(props.inbox.waha_session, session);
    }

    // Update form with WAHA config
    advancedConfig.value = {
      debug: wahaConfig.debug || false,
      metadata: wahaConfig.metadata || {},
      ignore_groups: wahaConfig.ignore?.groups || false,
      ignore_channels: wahaConfig.ignore?.channels !== false,
      ignore_status: wahaConfig.ignore?.status !== false,
      ignore_broadcast: wahaConfig.ignore?.broadcast !== false,
      proxy_server: wahaConfig.proxy?.server || '',
      proxy_username: wahaConfig.proxy?.username || '',
      proxy_password: '', // Never load password from server
      noweb_store_enabled: wahaConfig.noweb?.store?.enabled !== false,
      noweb_store_full_sync: wahaConfig.noweb?.store?.fullSync || false,
    };
    metadataString.value = JSON.stringify(
      advancedConfig.value.metadata,
      null,
      2
    );
  } catch (err) {
    console.error('Failed to load config from WAHA:', err);
    // Fallback to local data if WAHA is unavailable
    if (wahaSession.value) {
      advancedConfig.value = {
        debug: wahaSession.value.debug || false,
        metadata: wahaSession.value.metadata || {},
        ignore_groups: wahaSession.value.ignore_groups || false,
        ignore_channels: wahaSession.value.ignore_channels !== false,
        ignore_status: wahaSession.value.ignore_status !== false,
        ignore_broadcast: wahaSession.value.ignore_broadcast !== false,
        proxy_server: wahaSession.value.proxy_server || '',
        proxy_username: wahaSession.value.proxy_username || '',
        proxy_password: '',
        noweb_store_enabled: wahaSession.value.noweb_store_enabled !== false,
        noweb_store_full_sync: wahaSession.value.noweb_store_full_sync || false,
      };
      metadataString.value = JSON.stringify(
        advancedConfig.value.metadata,
        null,
        2
      );
    }
  }
};

const normalizeStatus = response => {
  // Prefer live WAHA status; fall back to persisted status.
  if (response?.data?.connected === true) return 'connected';

  const liveStatus =
    response?.data?.waha_status || response?.data?.waha_data?.status;
  const persistedStatus = response?.data?.status;
  const value = (liveStatus || persistedStatus || '').toString().toLowerCase();

  if (value === 'working') return 'connected';

  return value || 'pending';
};

const extractPhoneNumber = response => {
  const phone =
    response?.data?.phone_number ||
    response?.data?.waha_data?.me?.id?.split?.('@')?.[0];
  return phone || '';
};

const fetchStatus = async () => {
  if (!sessionId.value) return;

  try {
    const response = await WahaSessionsAPI.getStatus(sessionId.value);
    const previousNeedsQR = needsQRCode.value;

    status.value = normalizeStatus(response);
    phoneNumber.value = extractPhoneNumber(response);
    presence.value = response?.data?.waha_data?.presence || '';

    lastStatusCheckAt.value = Date.now();

    // Update local waha_data copy with latest info
    if (response?.data?.waha_data) {
      localWahaData.value = response.data.waha_data;
    }
    if (response?.data?.app) {
      localWahaData.value = { ...localWahaData.value, app: response.data.app };
    }

    // Start or stop polling based on QR code requirement
    if (needsQRCode.value && !previousNeedsQR) {
      startPolling();
    } else if (!needsQRCode.value && previousNeedsQR) {
      stopPolling();
    }
  } catch (err) {
    console.error('Failed to fetch WAHA status:', err);
  }
};

const fetchQRCode = async () => {
  if (!sessionId.value || !needsQRCode.value) return;

  try {
    loading.value = true;
    const response = await WahaSessionsAPI.getQRCode(sessionId.value, true);
    const newQrCode = response.data.qr_code || '';

    // Always update QR and force re-render
    if (newQrCode) {
      qrCode.value = newQrCode;
      qrCodeKey.value = Date.now(); // Force re-render with timestamp
      console.log('QR Code updated at:', new Date().toLocaleTimeString());
    }

    status.value = normalizeStatus(response) || status.value;
    if (qrCode.value) {
      expiresIn.value = 10; // WAHA QR codes effectively rotate fast
    }
  } catch (err) {
    useAlert(t('INBOX_MGMT.ADD.WAHA.QR_CODE_ERROR'));
  } finally {
    loading.value = false;
  }
};

const handleRestart = async () => {
  if (!sessionId.value) return;

  try {
    loading.value = true;
    await WahaSessionsAPI.restart(sessionId.value);
    useAlert(t('INBOX_MGMT.WAHA.RESTART_SUCCESS'));
    await fetchStatus();
    if (needsQRCode.value) {
      await fetchQRCode();
    }
  } catch (err) {
    useAlert(t('INBOX_MGMT.WAHA.RESTART_ERROR'));
  } finally {
    loading.value = false;
  }
};

const handleLogout = async () => {
  if (!sessionId.value) return;

  try {
    loading.value = true;
    await WahaSessionsAPI.logout(sessionId.value);
    useAlert(t('INBOX_MGMT.WAHA.LOGOUT_SUCCESS'));
    phoneNumber.value = '';
    qrCode.value = '';
    await fetchStatus();
  } catch (err) {
    useAlert(t('INBOX_MGMT.WAHA.LOGOUT_ERROR'));
  } finally {
    loading.value = false;
  }
};

const handleRecreateApp = async () => {
  if (!sessionId.value) return;

  try {
    loading.value = true;
    await WahaSessionsAPI.recreateApp(sessionId.value);
    useAlert(t('INBOX_MGMT.WAHA.RESTART_SUCCESS'));
  } catch (err) {
    useAlert(t('INBOX_MGMT.WAHA.RESTART_ERROR'));
  } finally {
    loading.value = false;
  }
};

const handleSaveAdvancedConfig = async () => {
  if (!sessionId.value) return;

  try {
    savingConfig.value = true;

    // Parse metadata JSON
    let metadata = {};
    if (metadataString.value.trim()) {
      try {
        metadata = JSON.parse(metadataString.value);
      } catch (e) {
        useAlert(t('INBOX_MGMT.WAHA.ADVANCED.METADATA_PARSE_ERROR'));
        return;
      }
    }

    const payload = {
      ...advancedConfig.value,
      metadata,
    };

    const response = await WahaSessionsAPI.updateConfig(
      sessionId.value,
      payload
    );

    // Update local wahaSession with response data
    if (response.data) {
      Object.assign(props.inbox.waha_session, response.data);
    }

    useAlert(t('INBOX_MGMT.WAHA.ADVANCED.CONFIG_SAVED'));

    // Reload config from WAHA to confirm changes
    await loadAdvancedConfig();

    emit('update');
  } catch (err) {
    console.error('Failed to save config:', err);
    useAlert(t('INBOX_MGMT.WAHA.ADVANCED.CONFIG_ERROR'));
  } finally {
    savingConfig.value = false;
  }
};

const startPolling = () => {
  // Stop any existing polling first
  stopPolling();

  // Only poll for QR code updates when needed
  if (!needsQRCode.value) {
    return;
  }

  fetchQRCode();

  scheduleNextTick();
};

const stopPolling = () => {
  if (refreshTimer.value) {
    clearTimeout(refreshTimer.value);
    refreshTimer.value = null;
  }

  isPolling.value = false;
};

const scheduleNextTick = () => {
  refreshTimer.value = setTimeout(runTick, TICK_INTERVAL_MS);
};

const runTick = async () => {
  if (!refreshTimer.value) return;

  if (isPolling.value) {
    scheduleNextTick();
    return;
  }

  isPolling.value = true;

  try {
    const now = Date.now();
    const needsQr = needsQRCode.value;
    let statusChecked = false;

    if (needsQr && now - lastStatusCheckAt.value >= STATUS_POLL_MS) {
      await fetchStatus();
      statusChecked = true;
    }

    if (expiresIn.value > 0) {
      expiresIn.value -= 1;
    }

    if (needsQr && expiresIn.value <= 0) {
      if (!statusChecked) {
        await fetchStatus();
      }

      if (needsQRCode.value) {
        await fetchQRCode();
      } else {
        stopPolling();
        return;
      }
    }

    if (!needsQRCode.value) {
      stopPolling();
    }
  } finally {
    isPolling.value = false;

    if (refreshTimer.value) {
      scheduleNextTick();
    }
  }
};

onMounted(async () => {
  if (wahaSession.value) {
    status.value = wahaSession.value.connected
      ? 'connected'
      : wahaSession.value.status;
    phoneNumber.value = wahaSession.value.phone_number || '';
    presence.value = wahaSession.value.waha_data?.presence || '';
    loadAdvancedConfig();

    await fetchStatus();

    if (needsQRCode.value) {
      startPolling();
    } else {
      stopPolling();
    }
  }
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div class="mx-8">
    <div
      v-if="!wahaSession"
      class="p-4 bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-700 rounded-lg"
    >
      <p class="text-slate-700 dark:text-slate-200">
        {{ $t('INBOX_MGMT.WAHA.NOT_CONFIGURED') }}
      </p>
    </div>

    <div v-else>
      <!-- Connection Status Overview -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.CONNECTION_STATUS')"
        :sub-title="$t('INBOX_MGMT.WAHA.CONNECTION_STATUS_DESC')"
      >
        <div class="md:max-w-4xl space-y-4">
          <!-- Status Badge & Quick Info -->
          <div
            class="flex flex-col sm:flex-row items-start sm:items-center gap-4"
          >
            <div
              class="inline-flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold border shadow-sm"
              :class="{
                'bg-green-50 text-green-700 border-green-200 dark:bg-green-900/20 dark:text-green-400 dark:border-green-800':
                  status === 'connected',
                'bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-900/20 dark:text-amber-400 dark:border-amber-800':
                  needsQRCode,
                'bg-red-50 text-red-700 border-red-200 dark:bg-red-900/20 dark:text-red-400 dark:border-red-800':
                  status === 'failed' || status === 'stopped',
                'bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-900/20 dark:text-slate-400 dark:border-slate-700':
                  !['connected', 'failed', 'stopped'].includes(status) &&
                  !needsQRCode,
              }"
            >
              <span
                class="inline-block w-2.5 h-2.5 rounded-full animate-pulse"
                :class="{
                  'bg-green-500': status === 'connected',
                  'bg-amber-500': needsQRCode,
                  'bg-red-500': status === 'failed' || status === 'stopped',
                  'bg-slate-400':
                    !['connected', 'failed', 'stopped'].includes(status) &&
                    !needsQRCode,
                }"
              />
              <span>{{ statusText }}</span>
            </div>
            <div
              v-if="presence"
              class="text-sm text-slate-600 dark:text-slate-400"
            >
              <span class="font-medium">{{
                $t('INBOX_MGMT.WAHA.PRESENCE')
              }}</span>
              <span class="ml-1">{{ presence }}</span>
            </div>
          </div>

          <!-- Connection Info Cards -->
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <!-- Phone Number -->
            <div
              class="p-4 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
            >
              <div class="mb-2">
                <p
                  class="text-xs font-semibold text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                >
                  {{ $t('INBOX_MGMT.WAHA.PHONE_NUMBER') }}
                </p>
              </div>
              <p
                class="text-base font-mono font-semibold text-slate-900 dark:text-slate-100"
              >
                {{ phoneNumber ? `+${phoneNumber}` : emDash }}
              </p>
            </div>

            <!-- Engine -->
            <div
              class="p-4 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
            >
              <div class="mb-2">
                <p
                  class="text-xs font-semibold text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                >
                  {{ $t('INBOX_MGMT.WAHA.ENGINE') }}
                </p>
              </div>
              <p
                class="text-base font-semibold text-slate-900 dark:text-slate-100"
              >
                {{ appInfo.engine || '—' }}
              </p>
            </div>

            <!-- WAHA Status -->
            <div
              class="p-4 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
            >
              <div class="mb-2">
                <p
                  class="text-xs font-semibold text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                >
                  {{ $t('INBOX_MGMT.WAHA.WAHA_STATUS_LABEL') }}
                </p>
              </div>
              <p
                class="text-base font-semibold text-slate-900 dark:text-slate-100"
              >
                {{ appInfo.remoteStatus || '—' }}
              </p>
            </div>
          </div>

          <!-- Status Message -->
          <div
            v-if="status === 'connected' || needsQRCode"
            class="p-4 rounded-lg"
            :class="{
              'bg-green-50 dark:bg-green-900/10': status === 'connected',
              'bg-amber-50 dark:bg-amber-900/10': needsQRCode,
            }"
          >
            <div>
              <p
                class="text-sm"
                :class="{
                  'text-green-800 dark:text-green-300': status === 'connected',
                  'text-amber-800 dark:text-amber-300': needsQRCode,
                }"
              >
                <span v-if="status === 'connected'">
                  {{
                    $t('INBOX_MGMT.WAHA.CONNECTED_DESC', {
                      phone: phoneNumber || '',
                    })
                  }}
                </span>
                <span v-else-if="needsQRCode">
                  {{ $t('INBOX_MGMT.WAHA.NEEDS_QR_DESC') }}
                </span>
              </p>
            </div>
          </div>
        </div>
      </SettingsSection>

      <!-- QR Code Section -->
      <SettingsSection
        v-if="needsQRCode"
        :title="$t('INBOX_MGMT.ADD.WAHA.QR_CODE_TITLE')"
        :sub-title="$t('INBOX_MGMT.WAHA.SCAN_QR_DESC')"
      >
        <div class="md:max-w-4xl">
          <div
            class="flex flex-col items-center gap-6 p-8 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900/50 dark:to-slate-900/30 border border-slate-200 dark:border-slate-800 rounded-xl shadow-sm"
          >
            <div class="flex items-center justify-center">
              <div
                v-if="loading && !qrCode"
                class="w-[280px] h-[280px] flex items-center justify-center bg-white dark:bg-slate-950 border-2 border-slate-200 dark:border-slate-700 rounded-2xl shadow-lg"
              >
                <Spinner size="" color-scheme="primary" />
              </div>

              <div
                v-else-if="qrCode"
                class="bg-white dark:bg-slate-950 p-5 rounded-2xl shadow-lg border-2 border-slate-200 dark:border-slate-700"
              >
                <img
                  :key="qrCodeKey"
                  :src="qrCodeSrc"
                  alt="WhatsApp QR Code"
                  class="w-[280px] h-[280px] object-contain"
                />
              </div>
            </div>

            <div class="text-center space-y-2">
              <h4
                class="text-base font-semibold text-slate-900 dark:text-slate-100"
              >
                {{ $t('INBOX_MGMT.WAHA.QR_SCAN_TITLE') }}
              </h4>
              <p class="text-sm text-slate-600 dark:text-slate-400">
                {{ $t('INBOX_MGMT.WAHA.QR_SCAN_INSTRUCTIONS') }}
              </p>
              <p class="text-xs text-slate-500 dark:text-slate-500 mt-2">
                {{
                  $t('INBOX_MGMT.ADD.WAHA.QR_CODE_EXPIRES', {
                    seconds: expiresIn,
                  })
                }}
              </p>
            </div>
          </div>
        </div>
      </SettingsSection>

      <!-- Session Management -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.SESSION_MANAGEMENT')"
        :sub-title="$t('INBOX_MGMT.WAHA.SESSION_MANAGEMENT_DESC')"
      >
        <div class="md:max-w-4xl">
          <div class="flex flex-wrap gap-3">
            <NextButton
              :disabled="loading"
              :is-loading="loading"
              @click="fetchStatus"
            >
              {{ $t('INBOX_MGMT.WAHA.REFRESH_STATUS') }}
            </NextButton>
            <NextButton :disabled="loading" @click="handleRestart">
              {{ $t('INBOX_MGMT.WAHA.RESTART') }}
            </NextButton>
            <NextButton :disabled="loading" @click="handleRecreateApp">
              {{ $t('INBOX_MGMT.WAHA.RECREATE_APP') }}
            </NextButton>
            <NextButton
              v-if="status === 'connected'"
              color-scheme="alert"
              :disabled="loading"
              @click="handleLogout"
            >
              {{ $t('INBOX_MGMT.WAHA.LOGOUT') }}
            </NextButton>
          </div>
        </div>
      </SettingsSection>

      <!-- WAHA Application Details -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.APP_INFO.TITLE')"
        :sub-title="$t('INBOX_MGMT.WAHA.APP_INFO.SUBTITLE')"
      >
        <div class="md:max-w-4xl space-y-6">
          <!-- Integration Configuration -->
          <div class="space-y-3">
            <h4
              class="text-sm font-semibold text-slate-700 dark:text-slate-300"
            >
              {{ $t('INBOX_MGMT.WAHA.INTEGRATION_CONFIG_TITLE') }}
            </h4>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <template v-if="appInfo.appId">
                <div class="space-y-2">
                  <label
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                  >
                    {{ $t('INBOX_MGMT.WAHA.WAHA_APP_ID') }}
                  </label>
                  <woot-code :script="appInfo.appId" />
                </div>
              </template>
              <template v-if="appInfo.webhook">
                <div class="space-y-2">
                  <label
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                  >
                    {{ $t('INBOX_MGMT.WAHA.WEBHOOK_URL') }}
                  </label>
                  <woot-code :script="appInfo.webhook" lang="html" />
                </div>
              </template>
              <template v-if="appInfo.url">
                <div class="space-y-2">
                  <label
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                  >
                    {{ $t('INBOX_MGMT.WAHA.WAHA_SERVER_URL') }}
                  </label>
                  <woot-code :script="appInfo.url" lang="html" />
                </div>
              </template>
              <template v-if="appInfo.inboxIdentifier">
                <div class="space-y-2">
                  <label
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
                  >
                    {{ $t('INBOX_MGMT.WAHA.INBOX_IDENTIFIER') }}
                  </label>
                  <woot-code :script="appInfo.inboxIdentifier" />
                </div>
              </template>
            </div>
          </div>

          <!-- Application Settings -->
          <div
            v-if="
              appInfo.locale ||
              appInfo.linkPreview ||
              appInfo.enabled !== undefined
            "
            class="space-y-3"
          >
            <h4
              class="text-sm font-semibold text-slate-700 dark:text-slate-300"
            >
              {{ $t('INBOX_MGMT.WAHA.APP_SETTINGS_TITLE') }}
            </h4>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
              <template v-if="appInfo.locale">
                <div
                  class="p-3 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
                >
                  <p
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >
                    {{ $t('INBOX_MGMT.WAHA.LOCALE') }}
                  </p>
                  <p
                    class="text-sm font-semibold text-slate-900 dark:text-slate-100"
                  >
                    {{ appInfo.locale }}
                  </p>
                </div>
              </template>
              <template v-if="appInfo.linkPreview">
                <div
                  class="p-3 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
                >
                  <p
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >
                    {{ $t('INBOX_MGMT.WAHA.LINK_PREVIEW') }}
                  </p>
                  <p
                    class="text-sm font-semibold text-slate-900 dark:text-slate-100"
                  >
                    {{ appInfo.linkPreview }}
                  </p>
                </div>
              </template>
              <template v-if="appInfo.enabled !== undefined">
                <div
                  class="p-3 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
                >
                  <p
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >
                    {{ $t('INBOX_MGMT.WAHA.STATUS') }}
                  </p>
                  <div class="flex items-center gap-2">
                    <span
                      class="inline-block w-2 h-2 rounded-full"
                      :class="appInfo.enabled ? 'bg-green-500' : 'bg-slate-400'"
                    />
                    <p
                      class="text-sm font-semibold text-slate-900 dark:text-slate-100"
                    >
                      {{
                        appInfo.enabled
                          ? $t('INBOX_MGMT.WAHA.ENABLED')
                          : $t('INBOX_MGMT.WAHA.DISABLED')
                      }}
                    </p>
                  </div>
                </div>
              </template>
            </div>
          </div>

          <!-- Internal References -->
          <div v-if="appInfo.accountId || appInfo.inboxId" class="space-y-3">
            <h4
              class="text-sm font-semibold text-slate-700 dark:text-slate-300"
            >
              {{ $t('INBOX_MGMT.WAHA.INTERNAL_REFERENCES_TITLE') }}
            </h4>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <template v-if="appInfo.accountId">
                <div
                  class="p-3 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
                >
                  <p
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >
                    {{ $t('INBOX_MGMT.WAHA.ACCOUNT_ID') }}
                  </p>
                  <p
                    class="text-sm font-mono font-semibold text-slate-900 dark:text-slate-100"
                  >
                    {{ appInfo.accountId }}
                  </p>
                </div>
              </template>
              <template v-if="appInfo.inboxId">
                <div
                  class="p-3 rounded-lg bg-slate-50 dark:bg-slate-900/50 border border-slate-200 dark:border-slate-800"
                >
                  <p
                    class="text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
                  >
                    {{ $t('INBOX_MGMT.WAHA.INBOX_ID') }}
                  </p>
                  <p
                    class="text-sm font-mono font-semibold text-slate-900 dark:text-slate-100"
                  >
                    {{ appInfo.inboxId }}
                  </p>
                </div>
              </template>
            </div>
          </div>
        </div>
      </SettingsSection>

      <!-- Session Information -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.SESSION_DETAILS')"
        :sub-title="$t('INBOX_MGMT.WAHA.SESSION_DETAILS_DESC')"
      >
        <div class="md:max-w-4xl space-y-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="space-y-2">
              <label
                class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('INBOX_MGMT.WAHA.SESSION_NAME_LABEL') }}
              </label>
              <woot-code :script="sessionName" />
            </div>
            <div class="space-y-2">
              <label
                class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
              >
                {{ $t('INBOX_MGMT.WAHA.INBOX_IDENTIFIER_LABEL') }}
              </label>
              <woot-code :script="inboxIdentifier" />
            </div>
          </div>

          <div v-if="webhookUrl" class="space-y-2">
            <label
              class="text-xs font-medium text-slate-600 dark:text-slate-400 uppercase tracking-wide"
            >
              {{ $t('INBOX_MGMT.WAHA.WEBHOOK_URL_LABEL') }}
            </label>
            <woot-code :script="webhookUrl" lang="html" />
          </div>
        </div>
      </SettingsSection>

      <!-- Advanced: General & Metadata -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.ADVANCED.METADATA')"
        :sub-title="$t('INBOX_MGMT.WAHA.ADVANCED.METADATA_DESC')"
      >
        <div class="space-y-4 md:max-w-4xl">
          <div class="border-b border-slate-200 dark:border-slate-700 pb-4">
            <label class="flex items-center gap-3 cursor-pointer">
              <input
                v-model="advancedConfig.debug"
                type="checkbox"
                class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500 dark:focus:ring-woot-600 dark:ring-offset-slate-800 focus:ring-2 dark:bg-slate-700 dark:border-slate-600"
              />
              <div>
                <span class="font-medium text-slate-900 dark:text-slate-100">
                  {{ $t('INBOX_MGMT.WAHA.ADVANCED.DEBUG') }}
                </span>
                <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                  {{ $t('INBOX_MGMT.WAHA.ADVANCED.DEBUG_DESC') }}
                </p>
              </div>
            </label>
          </div>
          <div class="w-full">
            <label class="block mb-2">
              <span class="font-medium text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.METADATA') }}
              </span>
              <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.METADATA_DESC') }}
              </p>
            </label>
            <textarea
              v-model="metadataString"
              rows="4"
              class="w-full px-3 py-2 text-sm font-mono border border-slate-300 dark:border-slate-600 rounded-md bg-slate-50 dark:bg-slate-900 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              placeholder="{}"
            />
          </div>
        </div>
      </SettingsSection>

      <!-- Advanced: Ignore Filters -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_TITLE')"
        :sub-title="$t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_DESC')"
      >
        <div class="space-y-3 md:max-w-4xl">
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.ignore_groups"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_GROUPS') }}
              </span>
            </div>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.ignore_channels"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_CHANNELS') }}
              </span>
            </div>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.ignore_status"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_STATUS') }}
              </span>
            </div>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.ignore_broadcast"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.IGNORE_BROADCAST') }}
              </span>
            </div>
          </label>
        </div>
      </SettingsSection>

      <!-- Advanced: Proxy -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.ADVANCED.PROXY_TITLE')"
        :sub-title="$t('INBOX_MGMT.WAHA.ADVANCED.PROXY_DESC')"
      >
        <div class="space-y-3 md:max-w-4xl">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ $t('INBOX_MGMT.WAHA.ADVANCED.PROXY_SERVER') }}
            </label>
            <input
              v-model="advancedConfig.proxy_server"
              type="text"
              class="w-full px-3 py-2 text-sm border border-slate-300 dark:border-slate-600 rounded-md bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              placeholder="proxy.example.com:3128"
            />
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.PROXY_USERNAME') }}
              </label>
              <input
                v-model="advancedConfig.proxy_username"
                type="text"
                class="w-full px-3 py-2 text-sm border border-slate-300 dark:border-slate-600 rounded-md bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                placeholder="username"
              />
            </div>
            <div>
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
              >
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.PROXY_PASSWORD') }}
              </label>
              <input
                v-model="advancedConfig.proxy_password"
                type="password"
                class="w-full px-3 py-2 text-sm border border-slate-300 dark:border-slate-600 rounded-md bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                placeholder="password"
              />
            </div>
          </div>
        </div>
      </SettingsSection>

      <!-- Advanced: NOWEB Store -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.ADVANCED.NOWEB_TITLE')"
        :sub-title="$t('INBOX_MGMT.WAHA.ADVANCED.NOWEB_DESC')"
      >
        <div class="space-y-3 md:max-w-4xl">
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.noweb_store_enabled"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.NOWEB_ENABLED') }}
              </span>
            </div>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              v-model="advancedConfig.noweb_store_full_sync"
              type="checkbox"
              class="w-4 h-4 text-woot-600 bg-slate-100 border-slate-300 rounded focus:ring-woot-500"
            />
            <div>
              <span class="text-sm text-slate-900 dark:text-slate-100">
                {{ $t('INBOX_MGMT.WAHA.ADVANCED.NOWEB_FULL_SYNC') }}
              </span>
            </div>
          </label>
        </div>
      </SettingsSection>

      <!-- Advanced: Save Action -->
      <SettingsSection
        :title="$t('INBOX_MGMT.WAHA.ADVANCED.SAVE')"
        :sub-title="$t('INBOX_MGMT.WAHA.ADVANCED.SUBTITLE')"
      >
        <div class="flex items-center gap-3 md:max-w-4xl">
          <NextButton
            :disabled="savingConfig"
            :is-loading="savingConfig"
            @click="handleSaveAdvancedConfig"
          >
            {{ $t('INBOX_MGMT.WAHA.ADVANCED.SAVE') }}
          </NextButton>
        </div>
      </SettingsSection>
    </div>
  </div>
</template>
