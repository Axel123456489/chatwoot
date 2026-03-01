<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from 'dashboard/components-next/message/bubbles/Base.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Audio from 'dashboard/components-next/message/chips/Audio.vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// Normalize call metadata and status accepting both snake_case and camelCase
const callData = computed(
  () => props.message.call_metadata || props.message.callMetadata || {}
);
const callInfo = computed(
  () => props.message.call_info || props.message.callInfo || {}
);

const callDirection = computed(() => {
  const dir =
    props.message.call_direction ??
    props.message.callDirection ??
    callData.value.call_direction ??
    callData.value.callDirection ??
    callInfo.value.call_direction ??
    callInfo.value.callDirection;
  return typeof dir === 'string' ? dir.toLowerCase() : null;
});

const rawCallStatus = computed(() => {
  const s = props.message.call_status ?? props.message.callStatus ?? '';
  const normalized =
    typeof s === 'string' ? s.toString().toLowerCase() : String(s || '').toLowerCase();
  // API returns unprefixed values ('initiated', 'completed', etc.)
  // Component expects prefixed form ('call_initiated', 'call_completed', etc.)
  // Normalize to always have the 'call_' prefix.
  if (normalized && !normalized.startsWith('call_')) {
    return `call_${normalized}`;
  }
  return normalized;
});

const isInitiated = computed(() => rawCallStatus.value === 'call_initiated');
const isCompleted = computed(() => rawCallStatus.value === 'call_completed');
const isSuccessful = computed(() =>
  ['call_connected', 'call_completed'].includes(rawCallStatus.value)
);
const isMetaError = computed(() =>
  rawCallStatus.value.startsWith('call_error_')
);
const isRejected = computed(() => rawCallStatus.value === 'call_rejected');
const isMissed = computed(() =>
  ['call_missed', 'call_cancelled', 'call_busy', 'call_no_connection'].includes(
    rawCallStatus.value
  )
);

const iconConfig = computed(() => {
  if (isSuccessful.value) {
    return { icon: 'i-ph-phone', bgColor: 'bg-n-teal-9' };
  }
  if (isMissed.value) {
    return { icon: 'i-ph-phone-x', bgColor: 'bg-n-amber-9' };
  }
  if (isRejected.value || isMetaError.value) {
    return { icon: 'i-ph-phone-x', bgColor: 'bg-n-ruby-9' };
  }
  if (isInitiated.value) {
    return callDirection.value === 'outbound'
      ? { icon: 'i-ph-phone-outgoing', bgColor: 'bg-n-blue-9' }
      : { icon: 'i-ph-phone-incoming', bgColor: 'bg-n-blue-9' };
  }
  return { icon: 'i-ph-phone-call', bgColor: 'bg-n-slate-9' };
});

const messageBgColor = computed(() => {
  if (isSuccessful.value) {
    return '!bg-n-teal-9/20';
  }
  if (isMissed.value) {
    return '!bg-n-amber-9/20';
  }
  if (isRejected.value || isMetaError.value) {
    return '!bg-n-ruby-9/20';
  }
  if (isInitiated.value) {
    return '!bg-n-blue-9/20';
  }

  return '';
});

// Status text
const statusText = computed(() => {
  const status = rawCallStatus.value;

  // Extract duration
  let duration = props.message.callDuration || props.message.call_duration;
  if (!duration && props.message.content) {
    const match = props.message.content.match(/(\d{2}:\d{2})/);
    if (match) {
      const [minutes, seconds] = match[1].split(':').map(Number);
      duration = minutes * 60 + seconds;
    }
  }

  const formattedDuration = formatDuration(duration);

  switch (status) {
    case 'call_initiated':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_INITIATED');
    case 'call_connected':
      return formattedDuration
        ? t('CONVERSATION.WHATSAPP_CALL.CALL_CONNECTED_WITH_DURATION', { duration: formattedDuration })
        : t('CONVERSATION.WHATSAPP_CALL.CALL_CONNECTED');
    case 'call_completed':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_COMPLETED', { duration: formattedDuration });
    case 'call_rejected':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_REJECTED');
    case 'call_missed':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_MISSED');
    case 'call_cancelled':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_CANCELLED');
    case 'call_busy':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_BUSY');
    case 'call_no_connection':
      return t('CONVERSATION.WHATSAPP_CALL.CALL_NO_CONNECTION');
    case 'call_error_unauthorized':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_UNAUTHORIZED');
    case 'call_error_no_balance':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_NO_BALANCE');
    case 'call_error_not_enabled':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_NOT_ENABLED');
    case 'call_error_rate_limit':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_RATE_LIMIT');
    case 'call_error_invalid':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_INVALID');
    case 'call_error_recipient_not_approved':
      return t('CONVERSATION.WHATSAPP_CALL.ERROR_RECIPIENT_NOT_APPROVED');
    default:
      return t('CONVERSATION.WHATSAPP_CALL.CALL_FAILED');
  }
});

const directionText = computed(() =>
  callDirection.value === 'inbound'
    ? t('CONVERSATION.WHATSAPP_CALL.INCOMING_CALL')
    : t('CONVERSATION.WHATSAPP_CALL.OUTGOING_CALL')
);

const formatDuration = seconds => {
  if (!seconds || seconds <= 0) return '00:00';
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
};

const hasRecording = computed(
  () => isCompleted.value && (props.message.attachments?.length || 0) > 0
);

const recordingDuration = computed(() => {
  // First try to get duration from call message
  let duration = props.message.callDuration || props.message.call_duration;
  if (!duration && props.message.content) {
    const match = props.message.content.match(/(\d{2}:\d{2})/);
    if (match) {
      const [minutes, seconds] = match[1].split(':').map(Number);
      duration = minutes * 60 + seconds;
    }
  }
  if (!duration) {
    duration =
      callData.value.recording_duration || callData.value.recordingDuration;
  }
  // Try to get duration from attachment metadata
  if (!duration && props.message.attachments?.length > 0) {
    const audioAttachment = props.message.attachments.find(a => {
      const fileType = a.fileType ?? a.file_type;
      return fileType === 'audio';
    });
    if (audioAttachment) {
      duration = audioAttachment.duration;
    }
  }
  return duration;
});

const recordingAttachment = computed(() => {
  if (!hasRecording.value) return null;

  const attachment = props.message.attachments.find(a => {
    const fileType = a.fileType ?? a.file_type;
    const extension = a.extension ?? a.ext ?? '';
    return (
      fileType === 'audio' ||
      (extension && extension.match(/mp3|wav|ogg|m4a|webm/))
    );
  });

  if (!attachment) return null;

  let extension = attachment.extension;
  if (!extension && attachment.dataUrl) {
    const match = attachment.dataUrl.match(/\.([a-z0-9]+)$/i);
    extension = match ? match[1] : 'webm';
  }

  return {
    dataUrl: attachment.dataUrl ?? attachment.data_url,
    fileType: attachment.fileType ?? attachment.file_type ?? 'audio',
    extension: extension || 'webm',
    transcribedText:
      attachment.transcribedText ?? attachment.transcribed_text ?? '',
  };
});
</script>

<template>
  <BaseBubble
    class="px-3 py-2.5"
    :class="messageBgColor"
    data-bubble-name="whatsapp-call"
  >
    <div class="flex gap-2.5 items-center min-w-56">
      <!-- Icon -->
      <div
        class="size-7 rounded-lg grid place-content-center flex-shrink-0"
        :class="iconConfig.bgColor"
      >
        <Icon :icon="iconConfig.icon" class="text-white size-3.5" />
      </div>

      <!-- Status + direction on one line -->
      <div class="flex-1 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">{{ statusText }}</span>
        <span class="text-xs text-n-slate-11 ml-1.5">· {{ directionText }}</span>
      </div>
    </div>

    <!-- Recording Player (full width, below header) -->
    <div v-if="hasRecording && recordingAttachment" class="mt-2">
      <Audio
        :attachment="recordingAttachment"
        :external-duration="recordingDuration"
      />
    </div>
  </BaseBubble>
</template>
