<script>
export default {
  name: 'CallErrorNotification',
  props: {
    error: {
      type: Object,
      default: null,
    },
    visible: {
      type: Boolean,
      default: false,
    },
    onRetry: {
      type: Function,
      default: null,
    },
  },
  computed: {
    title() {
      return (
        this.error?.title || this.$t('WHATSAPP_CALLS.ERRORS.DEFAULT_TITLE')
      );
    },
    message() {
      return (
        this.error?.message || this.$t('WHATSAPP_CALLS.ERRORS.DEFAULT_MESSAGE')
      );
    },
    severity() {
      return this.error?.severity || 'error';
    },
    retryable() {
      return this.error?.retryable || false;
    },
    showActions() {
      return this.retryable || this.showSupport;
    },
    showSupport() {
      // Show support button for critical errors
      return this.severity === 'critical';
    },
    errorIcon() {
      const icons = {
        critical: 'error-circle',
        error: 'warning',
        warning: 'info',
      };
      return icons[this.severity] || 'warning';
    },
  },
  methods: {
    close() {
      this.$emit('close');
    },
    retry() {
      if (this.onRetry) {
        this.onRetry();
      }
      this.close();
    },
    contactSupport() {
      // Open support URL or show contact modal
      window.open('https://www.chatwoot.com/support', '_blank');
    },
  },
};
</script>

<template>
  <div
    v-if="visible"
    class="call-error-notification"
    :class="`severity-${severity}`"
  >
    <div class="error-header">
      <fluent-icon :icon="errorIcon" size="20" class="error-icon" />
      <h4 class="error-title">{{ title }}</h4>
      <button class="close-button" @click="close">
        <fluent-icon icon="dismiss" size="16" />
      </button>
    </div>

    <p class="error-message">{{ message }}</p>

    <div v-if="showActions" class="error-actions">
      <woot-button
        v-if="retryable"
        size="small"
        variant="clear"
        color-scheme="primary"
        @click="retry"
      >
        {{ $t('WHATSAPP_CALLS.ERRORS.RETRY') }}
      </woot-button>

      <woot-button
        v-if="showSupport"
        size="small"
        variant="clear"
        color-scheme="secondary"
        @click="contactSupport"
      >
        {{ $t('WHATSAPP_CALLS.ERRORS.CONTACT_SUPPORT') }}
      </woot-button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.call-error-notification {
  position: fixed;
  top: var(--space-large);
  right: var(--space-large);
  max-width: 400px;
  background: var(--white);
  border-radius: var(--border-radius-large);
  box-shadow: var(--shadow-large);
  padding: var(--space-normal);
  z-index: 9999;
  animation: slideIn 0.3s ease-out;

  &.severity-critical {
    border-left: 4px solid var(--r-500);
  }

  &.severity-error {
    border-left: 4px solid var(--y-500);
  }

  &.severity-warning {
    border-left: 4px solid var(--y-300);
  }
}

.error-header {
  display: flex;
  align-items: center;
  gap: var(--space-small);
  margin-bottom: var(--space-small);
}

.error-icon {
  flex-shrink: 0;

  .severity-critical & {
    color: var(--r-500);
  }

  .severity-error & {
    color: var(--y-500);
  }

  .severity-warning & {
    color: var(--y-300);
  }
}

.error-title {
  flex: 1;
  margin: 0;
  font-size: var(--font-size-small);
  font-weight: var(--font-weight-medium);
  color: var(--s-900);
}

.close-button {
  flex-shrink: 0;
  padding: var(--space-micro);
  border: 0;
  background: transparent;
  cursor: pointer;
  color: var(--s-500);
  border-radius: var(--border-radius-small);

  &:hover {
    background: var(--s-50);
    color: var(--s-700);
  }
}

.error-message {
  margin: 0 0 var(--space-normal) 0;
  font-size: var(--font-size-mini);
  color: var(--s-700);
  line-height: 1.5;
}

.error-actions {
  display: flex;
  gap: var(--space-small);
  justify-content: flex-end;
}

@keyframes slideIn {
  from {
    transform: translateX(100%);
    opacity: 0;
  }
  to {
    transform: translateX(0);
    opacity: 1;
  }
}
</style>
