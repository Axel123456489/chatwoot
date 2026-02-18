<script>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

export default {
  name: 'CallControlPanel',
  components: {
    Avatar,
  },
  props: {
    callData: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isMinimized: false,
      isMuted: false,
      isOnHold: false,
      isEnding: false,
      callDuration: 0,
      durationInterval: null,
      errorMessage: null,
      callQuality: 'good', // good, fair, poor
    };
  },
  computed: {
    isCallActive() {
      return [
        'ringing',
        'accepted',
        'connecting',
        'connected',
        'holding',
      ].includes(this.callStatus);
    },
    callStatus() {
      return this.callData.status || 'initiated';
    },
    callId() {
      return this.callData.call_id;
    },
    conversationId() {
      return this.callData.conversation_id;
    },
    contactName() {
      return (
        this.callData.contact_name || this.$t('WHATSAPP_CALLS.UNKNOWN_CONTACT')
      );
    },
    contactNumber() {
      return this.callData.contact_number || '';
    },
    contactAvatar() {
      return this.callData.contact_avatar || '';
    },
    callDirection() {
      return this.callData.direction || 'inbound';
    },
    statusIcon() {
      const icons = {
        initiated: 'call',
        ringing: 'call',
        accepted: 'call-checkmark',
        connecting: 'arrow-sync',
        connected: 'call-checkmark',
        holding: 'pause',
        ended: 'call-end',
        failed: 'call-prohibited',
        rejected: 'call-end',
      };
      return icons[this.callStatus] || 'call';
    },
    statusText() {
      const texts = {
        initiated: this.$t('WHATSAPP_CALLS.STATUS.INITIATED'),
        ringing: this.$t('WHATSAPP_CALLS.STATUS.RINGING'),
        accepted: this.$t('WHATSAPP_CALLS.STATUS.ACCEPTED'),
        connecting: this.$t('WHATSAPP_CALLS.STATUS.CONNECTING'),
        connected: this.$t('WHATSAPP_CALLS.STATUS.CONNECTED'),
        holding: this.$t('WHATSAPP_CALLS.STATUS.ON_HOLD'),
        ended: this.$t('WHATSAPP_CALLS.STATUS.ENDED'),
        failed: this.$t('WHATSAPP_CALLS.STATUS.FAILED'),
        rejected: this.$t('WHATSAPP_CALLS.STATUS.REJECTED'),
      };
      return texts[this.callStatus] || this.callStatus;
    },
    directionText() {
      return this.callDirection === 'inbound'
        ? this.$t('WHATSAPP_CALLS.INCOMING_CALL')
        : this.$t('WHATSAPP_CALLS.OUTGOING_CALL');
    },
    formattedDuration() {
      const minutes = Math.floor(this.callDuration / 60);
      const seconds = this.callDuration % 60;
      return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    },
    callStateClass() {
      return `call-state-${this.callStatus}`;
    },
    canHold() {
      return this.callStatus === 'connected';
    },
    canTransfer() {
      return this.callStatus === 'connected' && !this.isOnHold;
    },
    showQualityIndicator() {
      return this.callStatus === 'connected' && this.callQuality !== 'good';
    },
    qualityIcon() {
      const icons = {
        good: 'checkmark-circle',
        fair: 'warning',
        poor: 'error-circle',
      };
      return icons[this.callQuality] || 'checkmark-circle';
    },
    qualityText() {
      const texts = {
        good: this.$t('WHATSAPP_CALLS.QUALITY.GOOD'),
        fair: this.$t('WHATSAPP_CALLS.QUALITY.FAIR'),
        poor: this.$t('WHATSAPP_CALLS.QUALITY.POOR'),
      };
      return texts[this.callQuality] || '';
    },
  },
  watch: {
    callStatus(newStatus, oldStatus) {
      if (newStatus === 'connected' && oldStatus !== 'connected') {
        this.startDurationCounter();
      }
      if (['ended', 'failed', 'rejected'].includes(newStatus)) {
        this.stopDurationCounter();
      }
    },
  },
  mounted() {
    if (this.callStatus === 'connected') {
      this.startDurationCounter();
    }
  },
  beforeUnmount() {
    this.stopDurationCounter();
  },
  methods: {
    toggleMinimize() {
      this.isMinimized = !this.isMinimized;
    },
    toggleMute() {
      this.isMuted = !this.isMuted;
      this.$emit('mute', { callId: this.callId, muted: this.isMuted });

      const message = this.isMuted
        ? this.$t('WHATSAPP_CALLS.MICROPHONE_MUTED')
        : this.$t('WHATSAPP_CALLS.MICROPHONE_UNMUTED');
      this.showAlert(message);
    },
    toggleHold() {
      if (!this.canHold) return;

      this.isOnHold = !this.isOnHold;
      this.$emit('hold', { callId: this.callId, onHold: this.isOnHold });

      const message = this.isOnHold
        ? this.$t('WHATSAPP_CALLS.CALL_ON_HOLD')
        : this.$t('WHATSAPP_CALLS.CALL_RESUMED');
      this.showAlert(message);
    },
    showTransferDialog() {
      if (!this.canTransfer) return;
      this.$emit('transfer', { callId: this.callId });
    },
    async endCall() {
      this.isEnding = true;

      try {
        this.$emit('end', {
          callId: this.callId,
          conversationId: this.conversationId,
        });
        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_ENDED'));
      } catch (error) {
        this.errorMessage = this.$t('WHATSAPP_CALLS.END_CALL_FAILED');
      } finally {
        this.isEnding = false;
      }
    },
    startDurationCounter() {
      if (this.durationInterval) return;

      this.durationInterval = setInterval(() => {
        this.callDuration += 1;
      }, 1000);
    },
    stopDurationCounter() {
      if (this.durationInterval) {
        clearInterval(this.durationInterval);
        this.durationInterval = null;
      }
    },
    updateCallQuality(quality) {
      this.callQuality = quality;
    },
    setError(message) {
      this.errorMessage = message;
      setTimeout(() => {
        this.errorMessage = null;
      }, 5000);
    },
  },
};
</script>

<template>
  <div v-if="isCallActive" class="call-control-panel" :class="callStateClass">
    <div class="call-header">
      <!-- Call Status Icon -->
      <div class="status-indicator">
        <fluent-icon
          :icon="statusIcon"
          size="20"
          :class="`status-${callStatus}`"
        />
        <span class="status-text">{{ statusText }}</span>
      </div>

      <!-- Call Duration -->
      <div class="call-duration">
        <fluent-icon icon="clock" size="16" />
        <span>{{ formattedDuration }}</span>
      </div>

      <!-- Minimize/Expand Button -->
      <button class="toggle-button" @click="toggleMinimize">
        <fluent-icon
          :icon="isMinimized ? 'chevron-up' : 'chevron-down'"
          size="16"
        />
      </button>
    </div>

    <transition name="expand">
      <div v-if="!isMinimized" class="call-body">
        <!-- Contact Information -->
        <div class="contact-info">
          <Avatar :src="contactAvatar" :name="contactName" :size="48" />
          <div class="contact-details">
            <h3 class="contact-name">{{ contactName }}</h3>
            <p class="contact-number">{{ contactNumber }}</p>
            <p class="call-direction">
              {{ directionText }}
            </p>
          </div>
        </div>

        <!-- Call Controls -->
        <div class="call-controls">
          <!-- Mute Button -->
          <woot-button
            :color-scheme="isMuted ? 'alert' : 'secondary'"
            :icon="isMuted ? 'mic-off' : 'mic-on'"
            size="medium"
            variant="smooth"
            @click="toggleMute"
          >
            {{
              isMuted ? $t('WHATSAPP_CALLS.UNMUTE') : $t('WHATSAPP_CALLS.MUTE')
            }}
          </woot-button>

          <!-- Hold Button -->
          <woot-button
            :color-scheme="isOnHold ? 'warning' : 'secondary'"
            icon="pause"
            size="medium"
            variant="smooth"
            :disabled="!canHold"
            @click="toggleHold"
          >
            {{
              isOnHold ? $t('WHATSAPP_CALLS.RESUME') : $t('WHATSAPP_CALLS.HOLD')
            }}
          </woot-button>

          <!-- Transfer Button -->
          <woot-button
            color-scheme="secondary"
            icon="arrow-forward"
            size="medium"
            variant="smooth"
            :disabled="!canTransfer"
            @click="showTransferDialog"
          >
            {{ $t('WHATSAPP_CALLS.TRANSFER') }}
          </woot-button>

          <!-- Hangup Button -->
          <woot-button
            color-scheme="alert"
            icon="call-end"
            size="medium"
            :is-loading="isEnding"
            @click="endCall"
          >
            {{ $t('WHATSAPP_CALLS.END_CALL') }}
          </woot-button>
        </div>

        <!-- Call Quality Indicator -->
        <div v-if="showQualityIndicator" class="call-quality">
          <fluent-icon
            :icon="qualityIcon"
            size="16"
            :class="`quality-${callQuality}`"
          />
          <span>{{ qualityText }}</span>
        </div>

        <!-- Error Message -->
        <div v-if="errorMessage" class="error-message">
          <fluent-icon icon="warning" size="16" />
          <span>{{ errorMessage }}</span>
        </div>
      </div>
    </transition>
  </div>
</template>

<style lang="scss" scoped>
.expand-enter-active,
.expand-leave-active {
  transition: all 0.3s ease;
  max-height: 500px;
  overflow: hidden;
}

.expand-enter-from,
.expand-leave-to {
  max-height: 0;
  opacity: 0;
}

.call-control-panel {
  position: fixed;
  bottom: var(--space-large);
  right: var(--space-large);
  width: 380px;
  background: var(--white);
  border-radius: var(--border-radius-large);
  box-shadow: var(--shadow-large);
  z-index: 9998;
  overflow: hidden;
  transition: all 0.3s ease;

  &.call-state-ringing {
    border-top: 4px solid var(--w-500);
  }

  &.call-state-connected {
    border-top: 4px solid var(--g-600);
  }

  &.call-state-holding {
    border-top: 4px solid var(--y-600);
  }

  &.call-state-failed,
  &.call-state-rejected {
    border-top: 4px solid var(--r-500);
  }

  .call-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-small) var(--space-medium);
    background: var(--s-50);
    border-bottom: 1px solid var(--s-100);

    .status-indicator {
      display: flex;
      align-items: center;
      gap: var(--space-micro);
      flex: 1;

      .status-text {
        font-size: var(--font-size-small);
        font-weight: var(--font-weight-medium);
        color: var(--s-800);
      }

      .status-ringing,
      .status-connecting {
        color: var(--w-500);
        animation: pulse 1.5s ease-in-out infinite;
      }

      .status-connected {
        color: var(--g-600);
      }

      .status-holding {
        color: var(--y-600);
      }

      .status-failed,
      .status-rejected {
        color: var(--r-500);
      }
    }

    .call-duration {
      display: flex;
      align-items: center;
      gap: var(--space-micro);
      font-size: var(--font-size-small);
      color: var(--s-700);
      font-weight: var(--font-weight-medium);
      font-variant-numeric: tabular-nums;
    }

    .toggle-button {
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

  .call-body {
    padding: var(--space-medium);

    .contact-info {
      display: flex;
      gap: var(--space-small);
      margin-bottom: var(--space-medium);
      align-items: center;

      .contact-details {
        flex: 1;
        min-width: 0;

        .contact-name {
          font-size: var(--font-size-medium);
          font-weight: var(--font-weight-bold);
          color: var(--s-900);
          margin: 0 0 var(--space-micro);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .contact-number {
          font-size: var(--font-size-small);
          color: var(--s-600);
          margin: 0 0 var(--space-micro);
        }

        .call-direction {
          font-size: var(--font-size-mini);
          color: var(--s-500);
          margin: 0;
        }
      }
    }

    .call-controls {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: var(--space-small);
      margin-bottom: var(--space-small);
    }

    .call-quality {
      display: flex;
      align-items: center;
      gap: var(--space-micro);
      padding: var(--space-small);
      background: var(--y-50);
      border-radius: var(--border-radius-small);
      font-size: var(--font-size-small);
      color: var(--s-700);
      margin-top: var(--space-small);

      .quality-fair {
        color: var(--y-600);
      }

      .quality-poor {
        color: var(--r-500);
      }
    }

    .error-message {
      display: flex;
      align-items: center;
      gap: var(--space-micro);
      padding: var(--space-small);
      background: var(--r-50);
      border-radius: var(--border-radius-small);
      font-size: var(--font-size-small);
      color: var(--r-700);
      margin-top: var(--space-small);
    }
  }
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.5;
  }
}

@media (max-width: 768px) {
  .call-control-panel {
    left: var(--space-small);
    right: var(--space-small);
    width: auto;
    bottom: var(--space-small);
  }
}
</style>
