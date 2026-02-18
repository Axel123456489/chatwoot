<script>
import { mapGetters } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import TransferCallModal from './TransferCallModal.vue';

export default {
  name: 'WhatsAppCallsManager',
  components: {
    TransferCallModal,
  },
  data() {
    return {
      showTransferModal: false,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
      currentAccountId: 'getCurrentAccountId',
      activeCall: 'whatsappCalls/getActiveCall',
      incomingCalls: 'whatsappCalls/getIncomingCalls',
    }),
  },
  mounted() {
    this.setupEventListeners();
  },
  beforeUnmount() {
    this.removeEventListeners();
  },
  methods: {
    setupEventListeners() {
      emitter.on('whatsapp_incoming_call', this.handleIncomingCall);
    },

    removeEventListeners() {
      emitter.off('whatsapp_incoming_call', this.handleIncomingCall);
    },

    handleIncomingCall(call) {
      // Play notification sound
      this.playNotificationSound();

      // Show browser notification if permitted
      this.showBrowserNotification(call);
    },

    playNotificationSound() {
      // Reuse existing audio notification system
      const audio = new Audio('/audio/dashboard/ding.mp3');
      audio.play().catch(() => {
        // Ignore if audio play fails (browser policy)
      });
    },

    showBrowserNotification(call) {
      if ('Notification' in window && Notification.permission === 'granted') {
        new Notification('Incoming WhatsApp Call', {
          body: `Call from ${call.contact_name || call.from_number}`,
          icon: '/dashboard/images/logo.png',
          tag: `whatsapp-call-${call.id}`,
        });
      }
    },

    handleShowIncomingCall(event) {
      const { call } = event.detail;
      // Call is already added to store by ActionCable connector
      // This event can be used for additional UI updates if needed
    },

    showAlert(message) {
      window.bus.$emit('newToastMessage', { message });
    },

    async acceptCall(callId) {
      try {
        // Call the API to accept the call
        const response = await this.$store.dispatch(
          'whatsappCalls/acceptCall',
          {
            accountId: this.currentAccountId,
            callId: callId,
          }
        );

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_ACCEPTED'));

        // Remove from incoming calls list
        await this.$store.dispatch('whatsappCalls/removeIncomingCall', callId);
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.ACCEPT_FAILED'));
        console.error('Failed to accept call:', error);
      }
    },

    async rejectCall(callId, reason = 'declined') {
      try {
        // Call the API to reject the call
        await this.$store.dispatch('whatsappCalls/rejectCall', {
          accountId: this.currentAccountId,
          callId: callId,
          reason: reason,
        });

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_REJECTED'));

        // Remove from incoming calls list
        await this.$store.dispatch('whatsappCalls/removeIncomingCall', callId);
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.REJECT_FAILED'));
        console.error('Failed to reject call:', error);
      }
    },

    dismissCall(callId) {
      // User dismissed the notification but call continues ringing
      this.$store.dispatch('whatsappCalls/rejectIncomingCall', callId);
    },

    toggleMute() {
      // Mute/unmute logic will be handled by WebRTC
      this.$emit('toggle-mute', this.activeCall.id);
    },

    toggleHold() {
      // Hold/unhold logic will be handled by media server
      this.$emit('toggle-hold', this.activeCall.id);
    },

    openTransferModal() {
      this.showTransferModal = true;
    },

    closeTransferModal() {
      this.showTransferModal = false;
    },

    async handleTransfer({ targetAgentId, targetInboxId }) {
      try {
        // Transfer call logic
        await this.$store.dispatch('whatsappCalls/transferCall', {
          accountId: this.currentAccountId,
          callId: this.activeCall.id,
          targetAgentId,
          targetInboxId,
        });

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_TRANSFERRED'));
        this.closeTransferModal();
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.TRANSFER_FAILED'));
        console.error('Failed to transfer call:', error);
      }
    },

    async endCall() {
      if (!this.activeCall) {
        return;
      }

      try {
        await this.$store.dispatch('whatsappCalls/terminateCall', {
          accountId: this.currentAccountId,
          callId: this.activeCall.id,
          conversationId: this.activeCall.conversation_id,
        });

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_ENDED'));
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.END_CALL_FAILED'));
        console.error('Failed to end call:', error);
      }
    },
  },
};
</script>

<template>
  <div class="whatsapp-calls-container">
    <!-- Transfer Call Modal (keep only this) -->
    <woot-modal v-model:show="showTransferModal" :on-close="closeTransferModal">
      <TransferCallModal
        v-if="showTransferModal"
        :call="activeCall"
        @transfer="handleTransfer"
        @close="closeTransferModal"
      />
    </woot-modal>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-calls-container {
  position: fixed;
  z-index: 9999;
  pointer-events: none;

  > * {
    pointer-events: auto;
  }
}
</style>
