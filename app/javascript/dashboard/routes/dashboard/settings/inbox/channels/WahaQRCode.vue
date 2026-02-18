<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import WahaSessionsAPI from 'dashboard/api/wahaSessions';
import Spinner from 'shared/components/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  sessionId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

const qrCodeDataUrl = ref('');
const expiresIn = ref(10);
const status = ref('pending');
const phoneNumber = ref('');
const loading = ref(true);
const error = ref('');
const refreshTimer = ref(null);
const isPolling = ref(false);
const lastStatusCheckAt = ref(0);
const hasRedirected = ref(false);
const sessionInboxId = ref(null);

const TICK_INTERVAL_MS = 1000;
const STATUS_POLL_MS = 5000;

const inboxId = computed(() => route.query.inbox_id || sessionInboxId.value);

const statusColor = computed(() => {
  switch (status.value) {
    case 'connected':
      return 'text-green-600';
    case 'scan_qr':
    case 'connecting':
    case 'starting':
      return 'text-yellow-600';
    case 'failed':
    case 'stopped':
      return 'text-red-600';
    default:
      return 'text-gray-600';
  }
});

const statusText = computed(() => {
  const key = status.value.toUpperCase().replace('_', '_');
  return t(`INBOX_MGMT.ADD.WAHA.STATUS.${key}`) || status.value;
});

const canRefresh = computed(() => {
  return (
    ['scan_qr', 'connecting', 'starting'].includes(status.value) &&
    !loading.value
  );
});

const fetchQRCode = async () => {
  try {
    loading.value = true;
    error.value = '';

    const response = await WahaSessionsAPI.getQRCode(props.sessionId, true);

    if (response.data.qr_code) {
      qrCodeDataUrl.value = response.data.qr_code;
      expiresIn.value = 10; // WAHA QR codes effectively expire quickly; force 10s refresh window
    }

    if (response.data.status) {
      status.value = response.data.status;
    }
  } catch (err) {
    error.value =
      err.response?.data?.error || t('INBOX_MGMT.ADD.WAHA.QR_CODE_ERROR');
    useAlert(error.value);
  } finally {
    loading.value = false;
  }
};

const fetchSession = async () => {
  try {
    const response = await WahaSessionsAPI.show(props.sessionId);
    sessionInboxId.value =
      response.data.inbox?.id || response.data.inbox_id || null;
  } catch (err) {
    // Soft fail; redirect fallback will go to inbox list
    console.error('Failed to fetch WAHA session:', err);
  }
};

const fetchStatus = async () => {
  try {
    const response = await WahaSessionsAPI.getStatus(props.sessionId);
    status.value = response.data.status;

    lastStatusCheckAt.value = Date.now();

    if (response.data.phone_number) {
      phoneNumber.value = response.data.phone_number;
    }

    if (status.value === 'connected') {
      stopRefresh();

      if (hasRedirected.value) return;
      hasRedirected.value = true;

      await store.dispatch('inboxes/get');

      if (inboxId.value) {
        router.replace({
          name: 'settings_inboxes_add_agents',
          params: { page: 'new', inbox_id: inboxId.value },
        });
      } else {
        router.replace({ name: 'settings_inbox_list' });
      }
    }
  } catch (err) {
    console.error('Failed to fetch status:', err);
  }
};

const startRefresh = () => {
  stopRefresh();
  fetchQRCode();
  fetchStatus();
  scheduleNextTick();
};

const stopRefresh = () => {
  if (refreshTimer.value) {
    clearTimeout(refreshTimer.value);
    refreshTimer.value = null;
  }
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
    let statusChecked = false;

    if (now - lastStatusCheckAt.value >= STATUS_POLL_MS) {
      await fetchStatus();
      statusChecked = true;
    }

    if (expiresIn.value > 0) {
      expiresIn.value -= 1;
    }

    const needsQr = ['scan_qr', 'starting', 'connecting'].includes(
      status.value
    );

    if (needsQr && expiresIn.value <= 0) {
      if (!statusChecked) {
        await fetchStatus();
      }

      if (status.value !== 'connected') {
        await fetchQRCode();
      }
    }
  } finally {
    isPolling.value = false;

    if (refreshTimer.value) {
      scheduleNextTick();
    }
  }
};

const handleRefresh = () => {
  fetchQRCode();
};

onMounted(() => {
  fetchSession();
  startRefresh();
});

onUnmounted(() => {
  stopRefresh();
});
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-6">
    <div class="space-y-6">
      <!-- Header -->
      <div class="text-center space-y-2">
        <h3 class="text-2xl font-semibold text-slate-900 dark:text-slate-100">
          {{ $t('INBOX_MGMT.ADD.WAHA.QR_CODE_TITLE') }}
        </h3>
        <p class="text-sm text-slate-600 dark:text-slate-400">
          {{ $t('INBOX_MGMT.ADD.WAHA.QR_CODE_DESCRIPTION') }}
        </p>
      </div>

      <!-- QR Code Card -->
      <div
        v-if="['scan_qr', 'connecting', 'starting'].includes(status)"
        class="flex flex-col items-center gap-6 p-8 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900/50 dark:to-slate-900/30 border border-slate-200 dark:border-slate-800 rounded-xl shadow-sm"
      >
        <div class="flex items-center justify-center">
          <div
            v-if="loading && !qrCodeDataUrl"
            class="w-[280px] h-[280px] flex items-center justify-center bg-white dark:bg-slate-950 border-2 border-slate-200 dark:border-slate-700 rounded-2xl shadow-lg"
          >
            <Spinner size="" color-scheme="primary" />
          </div>

          <div
            v-else-if="qrCodeDataUrl"
            class="bg-white dark:bg-slate-950 p-5 rounded-2xl shadow-lg border-2 border-slate-200 dark:border-slate-700"
          >
            <img
              :src="qrCodeDataUrl"
              alt="WhatsApp QR Code"
              class="w-[280px] h-[280px] object-contain"
            />
          </div>
        </div>

        <div class="text-center space-y-2">
          <h4
            class="text-base font-semibold text-slate-900 dark:text-slate-100"
          >
            Scan with WhatsApp
          </h4>
          <p class="text-sm text-slate-600 dark:text-slate-400">
            Open WhatsApp on your phone → Settings → Linked Devices → Link a
            Device
          </p>
          <p class="text-xs text-slate-500 dark:text-slate-500 mt-2">
            {{
              $t('INBOX_MGMT.ADD.WAHA.QR_CODE_EXPIRES', { seconds: expiresIn })
            }}
          </p>
        </div>
      </div>

      <!-- Connected State -->
      <div
        v-else-if="status === 'connected'"
        class="text-center p-8 bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-900/10 border border-green-200 dark:border-green-800 rounded-xl shadow-sm"
      >
        <div
          class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-green-100 dark:bg-green-900/30 mb-4"
        >
          <span class="text-4xl">✓</span>
        </div>
        <h4
          class="text-xl font-semibold text-green-800 dark:text-green-300 mb-2"
        >
          {{ $t('INBOX_MGMT.ADD.WAHA.CONNECTED') }}
        </h4>
        <p
          v-if="phoneNumber"
          class="text-base font-mono text-green-700 dark:text-green-400"
        >
          +{{ phoneNumber }}
        </p>
      </div>

      <!-- Error State -->
      <div
        v-else-if="error"
        class="text-center p-8 bg-gradient-to-br from-red-50 to-red-100 dark:from-red-900/20 dark:to-red-900/10 border border-red-200 dark:border-red-800 rounded-xl shadow-sm"
      >
        <div
          class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-red-100 dark:bg-red-900/30 mb-4"
        >
          <span class="text-4xl">✕</span>
        </div>
        <p class="text-red-700 dark:text-red-300 text-sm mb-4">{{ error }}</p>
        <NextButton variant="smooth" @click="handleRefresh">
          {{ $t('INBOX_MGMT.ADD.WAHA.TRY_AGAIN') }}
        </NextButton>
      </div>

      <!-- Status Badge -->
      <div class="flex justify-center">
        <div
          :class="statusColor"
          class="inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold border shadow-sm"
        >
          <span
            class="inline-block w-2.5 h-2.5 rounded-full animate-pulse"
            :class="statusColor.replace('text-', 'bg-')"
          />
          <span>{{ statusText }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
