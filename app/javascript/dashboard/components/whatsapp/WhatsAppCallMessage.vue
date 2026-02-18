<script setup>
import { computed } from 'vue';
import BaseBubble from 'dashboard/components-next/message/bubbles/Base.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Audio from 'dashboard/components-next/message/chips/Audio.vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

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
  return typeof s === 'string'
    ? s.toString().toLowerCase()
    : String(s || '').toLowerCase();
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
  let icon = 'phone-call';
  let bgColor = 'bg-n-slate-9';

  if (isSuccessful.value) {
    // Successful calls - green
    icon = 'phone';
    bgColor = 'bg-n-teal-9';
  } else if (isMissed.value) {
    // Missed/unanswered calls - amber
    icon = 'phone-x';
    bgColor = 'bg-n-amber-9';
  } else if (isRejected.value || isMetaError.value) {
    // Rejected or error calls - red
    icon = 'phone-x';
    bgColor = 'bg-n-ruby-9';
  } else if (isInitiated.value) {
    // Initiated/in-progress calls - blue
    icon =
      callDirection.value === 'outbound' ? 'phone-outgoing' : 'phone-incoming';
    bgColor = 'bg-n-blue-9';
  }

  return { icon, bgColor };
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
      return 'Call initiated...';
    case 'call_connected':
      return `Connected ${formattedDuration ? `• ${formattedDuration}` : ''}`;
    case 'call_completed':
      return `Call ended • ${formattedDuration}`;
    case 'call_rejected':
      return 'Call rejected';
    case 'call_missed':
      return 'Missed call';
    case 'call_cancelled':
      return 'Call cancelled';
    case 'call_busy':
      return 'User busy';
    case 'call_no_connection':
      return 'Connection failed';
    case 'call_error_unauthorized':
      return 'Error: Not authorized';
    case 'call_error_no_balance':
      return 'Error: Insufficient balance';
    case 'call_error_not_enabled':
      return 'Error: Calling not enabled';
    case 'call_error_rate_limit':
      return 'Error: Rate limit exceeded';
    case 'call_error_invalid':
      return 'Error: Invalid parameters';
    case 'call_error_recipient_not_approved':
      return 'Error: Recipient has not approved receiving calls';
    default:
      return 'Call failed';
  }
});

const directionText = computed(() =>
  callDirection.value === 'inbound' ? 'Incoming call' : 'Outgoing call'
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
    class="p-3"
    :class="messageBgColor"
    data-bubble-name="whatsapp-call"
  >
    <div class="flex gap-3 items-start min-w-64">
      <!-- Icon -->
      <div
        class="size-8 rounded-lg grid place-content-center flex-shrink-0"
        :class="iconConfig.bgColor"
      >
        <Icon :icon="`i-ph-${iconConfig.icon}`" class="text-white size-4" />
      </div>

      <!-- Content -->
      <div class="flex-1 min-w-0 space-y-1">
        <div class="text-sm font-medium text-n-slate-12">
          {{ statusText }}
        </div>
        <div class="text-xs text-n-slate-11">
          {{ directionText }}
        </div>

        <!-- Recording Player -->
        <div v-if="hasRecording && recordingAttachment" class="pt-2 space-y-2">
          <div class="flex items-center gap-2 text-xs text-n-slate-11">
            <Icon icon="i-ph-microphone" class="size-3.5" />
            <span>Recording</span>
            <span class="ml-auto tabular-nums">
              {{ formatDuration(recordingDuration) }}
            </span>
          </div>
          <Audio
            :attachment="recordingAttachment"
            :external-duration="recordingDuration"
          />
        </div>
      </div>
    </div>
  </BaseBubble>
</template>
