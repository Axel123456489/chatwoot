<script>
import { mapGetters } from 'vuex';

export default {
  name: 'IncomingCallNotification',
  props: {
    call: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isVisible: true,
      isRinging: true,
      isAccepting: false,
      isRejecting: false,
      callDuration: 0,
      durationInterval: null,
      ringtoneUrl: '/audio/ringtone.mp3',
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
    }),
    callerName() {
      return (
        this.call.contact_name ||
        this.call.from_number ||
        this.$t('WHATSAPP_CALLS.UNKNOWN_CALLER')
      );
    },
    callerNumber() {
      return this.call.from_number || '';
    },
    callId() {
      return this.call.call_id;
    },
    conversationId() {
      return this.call.conversation_id;
    },
    formattedDuration() {
      const minutes = Math.floor(this.callDuration / 60);
      const seconds = this.callDuration % 60;
      return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    },
  },
  mounted() {
    this.playRingtone();
    this.startDurationCounter();
    this.requestNotificationPermission();
    this.showBrowserNotification();
  },
  beforeUnmount() {
    this.stopRingtone();
    this.stopDurationCounter();
  },
  methods: {
    async acceptCall() {
      this.isAccepting = true;
      this.stopRingtone();

      try {
        // Emit event to parent to handle call acceptance
        this.$emit('accept', {
          callId: this.callId,
          conversationId: this.conversationId,
        });

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_ACCEPTED'));
        this.isVisible = false;
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.ACCEPT_FAILED'));
        console.error('Failed to accept call:', error);
      } finally {
        this.isAccepting = false;
      }
    },
    async rejectCall() {
      this.isRejecting = true;
      this.stopRingtone();

      try {
        // Emit event to parent to handle call rejection
        this.$emit('reject', {
          callId: this.callId,
          conversationId: this.conversationId,
        });

        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_REJECTED'));
        this.isVisible = false;
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.REJECT_FAILED'));
        console.error('Failed to reject call:', error);
      } finally {
        this.isRejecting = false;
      }
    },
    dismiss() {
      this.stopRingtone();
      this.isVisible = false;
      this.$emit('dismiss');
    },
    playRingtone() {
      if (this.$refs.ringtone) {
        this.$refs.ringtone.play().catch(err => {
          console.warn('Failed to play ringtone:', err);
        });
      }
    },
    stopRingtone() {
      if (this.$refs.ringtone) {
        this.$refs.ringtone.pause();
        this.$refs.ringtone.currentTime = 0;
      }
      this.isRinging = false;
    },
    startDurationCounter() {
      this.durationInterval = setInterval(() => {
        this.callDuration += 1;
      }, 1000);
    },
    stopDurationCounter() {
      if (this.durationInterval) {
        clearInterval(this.durationInterval);
      }
    },
    showAlert(message) {
      window.bus.$emit('newToastMessage', { message });
    },
    requestNotificationPermission() {
      if ('Notification' in window && Notification.permission === 'default') {
        Notification.requestPermission();
      }
    },
    showBrowserNotification() {
      if ('Notification' in window && Notification.permission === 'granted') {
        const notification = new Notification(
          this.$t('WHATSAPP_CALLS.INCOMING_CALL'),
          {
            body: `${this.$t('WHATSAPP_CALLS.CALL_FROM')} ${this.callerName}`,
            icon: '/favicon.png',
            tag: `call-${this.callId}`,
            requireInteraction: true,
          }
        );

        notification.onclick = () => {
          window.focus();
          notification.close();
        };
      }
    },
  },
};
</script>

<template>
  <transition name="slide-up">
    <div
      v-if="isVisible"
      class="incoming-call-notification"
      :class="{ 'is-ringing': isRinging }"
    >
      <div class="call-notification-content">
        <!-- Call Icon with Animation -->
        <div class="call-icon-wrapper">
          <fluent-icon
            icon="call"
            size="32"
            class="call-icon"
            :class="{ 'ringing-animation': isRinging }"
          />
        </div>

        <!-- Call Information -->
        <div class="call-info">
          <h3 class="call-title">
            {{ $t('WHATSAPP_CALLS.INCOMING_CALL') }}
          </h3>
          <p class="caller-name">
            {{ callerName }}
          </p>
          <p class="caller-number">
            {{ callerNumber }}
          </p>
          <p v-if="callDuration" class="call-duration">
            {{ formattedDuration }}
          </p>
        </div>

        <!-- Call Actions -->
        <div class="call-actions">
          <woot-button
            color-scheme="success"
            icon="checkmark-circle"
            size="large"
            :is-loading="isAccepting"
            :disabled="isRejecting"
            @click="acceptCall"
          >
            {{ $t('WHATSAPP_CALLS.ACCEPT') }}
          </woot-button>
          <woot-button
            color-scheme="alert"
            icon="dismiss-circle"
            size="large"
            :is-loading="isRejecting"
            :disabled="isAccepting"
            @click="rejectCall"
          >
            {{ $t('WHATSAPP_CALLS.REJECT') }}
          </woot-button>
        </div>

        <!-- Close Button -->
        <button class="close-button" @click="dismiss">
          <fluent-icon icon="dismiss" size="16" />
        </button>
      </div>

      <!-- Ringtone Audio -->
      <audio ref="ringtone" loop :src="ringtoneUrl" />
    </div>
  </transition>
</template>

<style lang="scss" scoped>
@keyframes slide-up {
  from {
    transform: translateY(100%);
    opacity: 0;
  }
  to {
    transform: translateY(0);
    opacity: 1;
  }
}

@keyframes ring-pulse {
  0%,
  100% {
    transform: scale(1);
    opacity: 1;
  }
  50% {
    transform: scale(1.1);
    opacity: 0.8;
  }
}

.slide-up-enter-active {
  animation: slide-up 0.3s ease-out;
}

.slide-up-leave-active {
  animation: slide-up 0.3s ease-in reverse;
}

.incoming-call-notification {
  position: fixed;
  bottom: var(--space-large);
  right: var(--space-large);
  width: 400px;
  background: var(--white);
  border-radius: var(--border-radius-large);
  box-shadow: var(--shadow-large);
  z-index: 9999;
  overflow: hidden;

  &.is-ringing {
    animation: ring-pulse 1s ease-in-out infinite;
  }

  .call-notification-content {
    padding: var(--space-medium);
    display: flex;
    flex-direction: column;
    gap: var(--space-medium);
    position: relative;
  }

  .call-icon-wrapper {
    display: flex;
    justify-content: center;
    padding: var(--space-small) 0;

    .call-icon {
      color: var(--g-600);

      &.ringing-animation {
        animation: ring-pulse 1.5s ease-in-out infinite;
      }
    }
  }

  .call-info {
    text-align: center;

    .call-title {
      font-size: var(--font-size-large);
      font-weight: var(--font-weight-bold);
      color: var(--s-900);
      margin: 0 0 var(--space-small);
    }

    .caller-name {
      font-size: var(--font-size-medium);
      font-weight: var(--font-weight-medium);
      color: var(--s-800);
      margin: 0 0 var(--space-micro);
    }

    .caller-number {
      font-size: var(--font-size-small);
      color: var(--s-600);
      margin: 0 0 var(--space-small);
    }

    .call-duration {
      font-size: var(--font-size-small);
      color: var(--s-500);
      font-weight: var(--font-weight-medium);
      margin: 0;
    }
  }

  .call-actions {
    display: flex;
    gap: var(--space-small);
    justify-content: center;

    button {
      flex: 1;
    }
  }

  .close-button {
    position: absolute;
    top: var(--space-small);
    right: var(--space-small);
    background: transparent;
    border: 0;
    cursor: pointer;
    padding: var(--space-micro);
    color: var(--s-600);
    border-radius: var(--border-radius-small);
    transition: all 0.2s ease;

    &:hover {
      background: var(--s-100);
      color: var(--s-800);
    }
  }
}

@media (max-width: 768px) {
  .incoming-call-notification {
    left: var(--space-small);
    right: var(--space-small);
    width: auto;
    bottom: var(--space-small);
  }
}
</style>
