<script setup>
import { computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useWhatsAppCall } from 'dashboard/composables/useWhatsAppCall';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';

const props = defineProps({
  conversationId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  contactName: { type: String, default: 'Unknown' },
  contactAvatar: { type: String, default: '' },
  callDirection: { type: String, default: 'outbound' }, // outbound | inbound
  sdpOffer: { type: String, default: '' }, // Only for inbound calls
});

const emit = defineEmits(['call-ended', 'call-connected']);

const store = useStore();

const {
  callStatus,
  isMuted,
  formattedDuration,
  prepareMediaStream,
  initiateCall,
  answerCall,
  endCall,
  toggleMute,
} = useWhatsAppCall();

// Get conversation to extract account_id
const conversation = computed(() =>
  store.getters.getConversationById(props.conversationId)
);

const accountId = computed(() => conversation.value?.account_id);

// Listen for call panel close event
const handleCallPanelClose = data => {
  if (data.conversationId === props.conversationId) {
    emit('call-ended');
  }
};

// Initialize call based on direction
onMounted(() => {
  // Set initial status for inbound calls
  if (props.callDirection === 'inbound') {
    callStatus.value = 'ringing';
  }

  // Listen for call termination events
  emitter.on('whatsapp-call-panel-close', handleCallPanelClose);

  // Pre-request microphone access for faster call initiation
  // This happens in background and doesn't block the UI
  if (props.callDirection === 'outbound') {
    prepareMediaStream();
  }

  if (props.callDirection === 'outbound') {
    const conv = conversation.value;
    if (conv && conv.account_id) {
      initiateCall({
        accountId: conv.account_id,
        conversationId: props.conversationId,
        callId: props.callId,
      })
        .then(result => {
          if (result && result.success) {
            emit('call-connected');
          } else if (result && !result.success) {
            // Call setup failed, close the panel
            console.error(
              '[WhatsAppCallPanel] Call setup returned failure:',
              result.error
            );
            emit('call-ended');
          }
        })
        .catch(error => {
          console.error('[WhatsAppCallPanel] Call initiation failed:', error);
          // Close the panel when call initiation fails
          emit('call-ended');
        });
    } else {
      console.error(
        '[WhatsAppCallPanel] Cannot start call - conversation or account_id missing:',
        conv
      );
      emit('call-ended');
    }
  }
});

onBeforeUnmount(() => {
  // Clean up event listener
  emitter.off('whatsapp-call-panel-close', handleCallPanelClose);
});

const statusText = computed(() => {
  switch (callStatus.value) {
    case 'connecting':
      return 'Connecting...';
    case 'ringing':
      return 'Ringing...';
    case 'connected':
      return formattedDuration.value;
    case 'ended':
      return 'Call ended';
    default:
      return 'Initializing...';
  }
});

const statusColor = computed(() => {
  switch (callStatus.value) {
    case 'connected':
      return 'text-n-teal-9';
    case 'ringing':
    case 'connecting':
      return 'text-n-amber-9';
    case 'ended':
      return 'text-n-slate-11';
    default:
      return 'text-n-slate-10';
  }
});

const handleEndCall = () => {
  endCall();
  emit('call-ended');
};

const handleAnswerCall = async () => {
  const result = await answerCall({
    accountId: accountId.value,
    sdpOffer: props.sdpOffer,
    conversationId: props.conversationId,
    callId: props.callId,
  });

  if (result.success) {
    emit('call-connected');
  }
};
</script>

<template>
  <div
    class="whatsapp-call-panel flex flex-col bg-n-solid-2 rounded-xl shadow-xl outline outline-1 outline-n-strong p-4 w-80"
  >
    <!-- Header -->
    <div class="flex items-center gap-3 mb-4">
      <div
        class="relative ring-2 rounded-full inline-flex"
        :class="{
          'ring-n-teal-9 animate-pulse':
            callStatus === 'ringing' || callStatus === 'connecting',
          'ring-n-teal-9': callStatus === 'connected',
          'ring-n-slate-7': callStatus === 'ended',
        }"
      >
        <img
          v-if="contactAvatar"
          :src="contactAvatar"
          :alt="contactName"
          class="w-12 h-12 rounded-full object-cover"
        />
        <div
          v-else
          class="w-12 h-12 rounded-full bg-n-slate-5 flex items-center justify-center text-n-slate-12 font-medium"
        >
          {{ contactName.charAt(0).toUpperCase() }}
        </div>
      </div>

      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate mb-0">
          {{ contactName }}
        </p>
        <p class="text-xs font-mono" :class="statusColor">
          {{ statusText }}
        </p>
      </div>

      <Icon icon="i-logos-whatsapp-icon" class="text-2xl shrink-0" />
    </div>

    <!-- Call Status Indicator -->
    <div
      v-if="callStatus === 'connecting' || callStatus === 'ringing'"
      class="flex items-center justify-center gap-2 mb-4 text-sm text-n-slate-11"
    >
      <div class="animate-spin">
        <Icon icon="i-ph-spinner" />
      </div>
      <span>{{
        callStatus === 'connecting'
          ? 'Establishing connection...'
          : 'Calling...'
      }}</span>
    </div>

    <!-- Controls -->
    <div class="flex justify-center gap-3">
      <!-- Mute/Unmute Button -->
      <button
        v-if="callStatus === 'connected'"
        type="button"
        class="flex justify-center items-center w-12 h-12 rounded-full transition-colors"
        :class="
          isMuted
            ? 'bg-n-ruby-9 hover:bg-n-ruby-10'
            : 'bg-n-slate-5 hover:bg-n-slate-6'
        "
        @click="toggleMute"
      >
        <Icon
          :icon="
            isMuted ? 'i-ph-microphone-slash-bold' : 'i-ph-microphone-bold'
          "
          class="text-lg"
          :class="isMuted ? 'text-white' : 'text-n-slate-12'"
        />
      </button>

      <!-- Answer Button (for incoming calls) -->
      <button
        v-if="callDirection === 'inbound' && callStatus === 'ringing'"
        type="button"
        class="flex justify-center items-center w-12 h-12 bg-n-teal-9 hover:bg-n-teal-10 rounded-full transition-colors"
        @click="handleAnswerCall"
      >
        <Icon icon="i-ph-phone-bold" class="text-lg text-white" />
      </button>

      <!-- End Call Button -->
      <button
        v-if="callStatus !== 'ended'"
        type="button"
        class="flex justify-center items-center w-12 h-12 bg-n-ruby-9 hover:bg-n-ruby-10 rounded-full transition-colors"
        @click="handleEndCall"
      >
        <Icon icon="i-ph-phone-x-bold" class="text-lg text-white" />
      </button>
    </div>

    <!-- Audio Elements (hidden) -->
    <audio autoplay />
  </div>
</template>

<style scoped>
.whatsapp-call-panel {
  user-select: none;
}
</style>
