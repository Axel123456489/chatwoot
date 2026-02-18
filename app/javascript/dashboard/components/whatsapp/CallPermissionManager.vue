<script>
import Spinner from 'shared/components/Spinner.vue';
import timeMixin from 'dashboard/mixins/time';
import WhatsappCallsAPI from '../../api/whatsapp/calls';

export default {
  name: 'CallPermissionManager',
  components: {
    Spinner,
  },
  mixins: [timeMixin],
  props: {
    contactId: {
      type: [Number, String],
      required: true,
    },
    inboxId: {
      type: [Number, String],
      required: true,
    },
    accountId: {
      type: [Number, String],
      required: true,
    },
  },
  data() {
    return {
      permissionStatus: null,
      isLoading: false,
      isRequesting: false,
      isRefreshing: false,
      error: null,
    };
  },
  computed: {
    canRequestPermission() {
      return (
        !this.permissionStatus ||
        this.permissionStatus.status === 'not_requested' ||
        this.permissionStatus.status === 'denied' ||
        this.permissionStatus.status === 'expired'
      );
    },
    callsPercentage() {
      if (!this.permissionStatus) return 0;
      return (this.permissionStatus.remaining_calls / 10) * 100;
    },
  },
  mounted() {
    this.loadPermission();
  },
  methods: {
    showAlert(message) {
      window.bus.$emit('newToastMessage', { message });
    },
    async loadPermission() {
      this.isLoading = true;
      this.error = null;

      try {
        const response = await WhatsappCallsAPI.getPermission({
          accountId: this.accountId,
          contactId: this.contactId,
          inboxId: this.inboxId,
        });

        this.permissionStatus = response.data.permission;
      } catch (error) {
        this.error =
          error.message || this.$t('WHATSAPP_CALLS.PERMISSIONS.LOAD_ERROR');
        console.error('Failed to load permission:', error);
      } finally {
        this.isLoading = false;
      }
    },

    async requestPermission() {
      this.isRequesting = true;

      try {
        const response = await WhatsappCallsAPI.requestPermission({
          accountId: this.accountId,
          contactId: this.contactId,
          inboxId: this.inboxId,
        });

        this.permissionStatus = response.data.permission;
        this.showAlert(this.$t('WHATSAPP_CALLS.PERMISSIONS.REQUEST_SENT'));
        this.$emit('permission-requested', this.permissionStatus);
      } catch (error) {
        const errorMessage = error.response?.data?.error || error.message;
        this.showAlert(errorMessage);
        console.error('Failed to request permission:', error);
      } finally {
        this.isRequesting = false;
      }
    },

    async refreshPermission() {
      this.isRefreshing = true;

      try {
        await this.loadPermission();
        this.showAlert(this.$t('WHATSAPP_CALLS.PERMISSIONS.REFRESHED'));
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.PERMISSIONS.REFRESH_ERROR'));
      } finally {
        this.isRefreshing = false;
      }
    },

    getStatusIcon() {
      const icons = {
        not_requested: 'call-prohibited',
        pending: 'clock',
        granted: 'checkmark-circle',
        denied: 'dismiss-circle',
        expired: 'warning',
        revoked: 'block',
      };
      return icons[this.permissionStatus.status] || 'info';
    },

    getStatusTitle() {
      const titles = {
        not_requested: this.$t(
          'WHATSAPP_CALLS.PERMISSIONS.STATUS.NOT_REQUESTED_TITLE'
        ),
        pending: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.PENDING_TITLE'),
        granted: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.GRANTED_TITLE'),
        denied: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.DENIED_TITLE'),
        expired: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.EXPIRED_TITLE'),
        revoked: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.REVOKED_TITLE'),
      };
      return titles[this.permissionStatus.status] || '';
    },

    getStatusDescription() {
      const descriptions = {
        not_requested: this.$t(
          'WHATSAPP_CALLS.PERMISSIONS.STATUS.NOT_REQUESTED_DESC'
        ),
        pending: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.PENDING_DESC'),
        granted: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.GRANTED_DESC'),
        denied: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.DENIED_DESC'),
        expired: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.EXPIRED_DESC'),
        revoked: this.$t('WHATSAPP_CALLS.PERMISSIONS.STATUS.REVOKED_DESC'),
      };
      return descriptions[this.permissionStatus.status] || '';
    },

    formatDate(dateString) {
      return this.dynamicTime(dateString);
    },
  },
};
</script>

<template>
  <div class="call-permission-manager">
    <!-- Header -->
    <div class="manager-header">
      <h3 class="title">
        {{ $t('WHATSAPP_CALLS.PERMISSIONS.TITLE') }}
      </h3>
      <p class="subtitle">
        {{ $t('WHATSAPP_CALLS.PERMISSIONS.SUBTITLE') }}
      </p>
    </div>

    <!-- Permission Status Card -->
    <div
      v-if="permissionStatus"
      class="permission-card"
      :class="`status-${permissionStatus.status}`"
    >
      <div class="card-icon">
        <fluent-icon :icon="getStatusIcon()" size="32" />
      </div>

      <div class="card-content">
        <h4 class="card-title">
          {{ getStatusTitle() }}
        </h4>

        <p class="card-description">
          {{ getStatusDescription() }}
        </p>

        <!-- Remaining Calls -->
        <div v-if="permissionStatus.granted" class="remaining-calls">
          <div class="calls-progress">
            <div class="progress-bar">
              <div
                class="progress-fill"
                :style="{ width: `${callsPercentage}%` }"
              />
            </div>
            <span class="calls-count">
              {{ permissionStatus.remaining_calls }} / 10
              {{ $t('WHATSAPP_CALLS.PERMISSIONS.CALLS_REMAINING') }}
            </span>
          </div>

          <!-- Expiration -->
          <div v-if="permissionStatus.expires_at" class="expiration-info">
            <fluent-icon icon="calendar-clock" size="16" />
            <span>
              {{ $t('WHATSAPP_CALLS.PERMISSIONS.EXPIRES_AT') }}:
              {{ formatDate(permissionStatus.expires_at) }}
            </span>
          </div>
        </div>

        <!-- Actions -->
        <div class="card-actions">
          <!-- Request Permission -->
          <woot-button
            v-if="canRequestPermission"
            color-scheme="primary"
            :is-loading="isRequesting"
            @click="requestPermission"
          >
            <fluent-icon icon="call" size="16" />
            {{ $t('WHATSAPP_CALLS.PERMISSIONS.REQUEST') }}
          </woot-button>

          <!-- Pending State -->
          <woot-button
            v-else-if="permissionStatus.status === 'pending'"
            variant="clear"
            disabled
          >
            <fluent-icon icon="clock" size="16" />
            {{ $t('WHATSAPP_CALLS.PERMISSIONS.PENDING') }}
          </woot-button>

          <!-- Refresh -->
          <woot-button
            v-if="permissionStatus.status !== 'not_requested'"
            variant="clear"
            size="small"
            :is-loading="isRefreshing"
            @click="refreshPermission"
          >
            <fluent-icon icon="arrow-sync" size="16" />
            {{ $t('WHATSAPP_CALLS.PERMISSIONS.REFRESH') }}
          </woot-button>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div v-else-if="isLoading" class="loading-state">
      <Spinner size="small" />
      <p>{{ $t('WHATSAPP_CALLS.PERMISSIONS.LOADING') }}</p>
    </div>

    <!-- Error State -->
    <div v-else-if="error" class="error-state">
      <fluent-icon icon="error-circle" size="32" />
      <p>{{ error }}</p>
      <woot-button variant="clear" @click="loadPermission">
        {{ $t('WHATSAPP_CALLS.PERMISSIONS.RETRY') }}
      </woot-button>
    </div>

    <!-- Instructions -->
    <div class="instructions-section">
      <h4 class="section-title">
        {{ $t('WHATSAPP_CALLS.PERMISSIONS.HOW_IT_WORKS') }}
      </h4>

      <ol class="instructions-list">
        <li>
          <fluent-icon icon="send" size="20" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.STEP_1') }}</span>
        </li>
        <li>
          <fluent-icon icon="person-available" size="20" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.STEP_2') }}</span>
        </li>
        <li>
          <fluent-icon icon="checkmark-circle" size="20" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.STEP_3') }}</span>
        </li>
        <li>
          <fluent-icon icon="call" size="20" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.STEP_4') }}</span>
        </li>
      </ol>
    </div>

    <!-- Limitations -->
    <div class="limitations-section">
      <h4 class="section-title">
        {{ $t('WHATSAPP_CALLS.PERMISSIONS.LIMITATIONS_TITLE') }}
      </h4>

      <ul class="limitations-list">
        <li>
          <fluent-icon icon="info" size="16" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.LIMIT_DAILY') }}</span>
        </li>
        <li>
          <fluent-icon icon="info" size="16" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.LIMIT_PERMISSION') }}</span>
        </li>
        <li>
          <fluent-icon icon="info" size="16" />
          <span>{{ $t('WHATSAPP_CALLS.PERMISSIONS.LIMIT_RENEWAL') }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.call-permission-manager {
  padding: var(--space-normal);
}

.manager-header {
  margin-bottom: var(--space-large);

  .title {
    margin: 0 0 var(--space-micro);
    font-size: var(--font-size-large);
    font-weight: var(--font-weight-bold);
    color: var(--s-900);
  }

  .subtitle {
    margin: 0;
    font-size: var(--font-size-small);
    color: var(--s-600);
  }
}

.permission-card {
  display: flex;
  gap: var(--space-normal);
  padding: var(--space-large);
  border-radius: var(--border-radius-large);
  background: var(--white);
  border: 2px solid var(--s-200);
  margin-bottom: var(--space-large);

  &.status-granted {
    border-color: var(--g-300);
    background: var(--g-25);
  }

  &.status-pending {
    border-color: var(--y-300);
    background: var(--y-25);
  }

  &.status-denied,
  &.status-revoked {
    border-color: var(--r-300);
    background: var(--r-25);
  }

  .card-icon {
    flex-shrink: 0;
  }

  .card-content {
    flex: 1;
  }

  .card-title {
    margin: 0 0 var(--space-small);
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-bold);
    color: var(--s-900);
  }

  .card-description {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-small);
    color: var(--s-700);
  }

  .remaining-calls {
    margin-bottom: var(--space-normal);
  }

  .calls-progress {
    margin-bottom: var(--space-small);

    .progress-bar {
      height: 8px;
      background: var(--s-100);
      border-radius: 4px;
      overflow: hidden;
      margin-bottom: var(--space-micro);

      .progress-fill {
        height: 100%;
        background: var(--g-500);
        transition: width 0.3s ease;
      }
    }

    .calls-count {
      font-size: var(--font-size-mini);
      font-weight: var(--font-weight-medium);
      color: var(--s-700);
    }
  }

  .expiration-info {
    display: flex;
    align-items: center;
    gap: var(--space-micro);
    font-size: var(--font-size-mini);
    color: var(--s-600);
  }

  .card-actions {
    display: flex;
    gap: var(--space-small);
    flex-wrap: wrap;
  }
}

.loading-state,
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--space-larger);
  text-align: center;
  color: var(--s-600);

  p {
    margin: var(--space-small) 0;
    font-size: var(--font-size-small);
  }
}

.instructions-section,
.limitations-section {
  margin-bottom: var(--space-large);

  .section-title {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-medium);
    color: var(--s-900);
  }
}

.instructions-list {
  list-style: none;
  padding: 0;
  margin: 0;
  counter-reset: step-counter;

  li {
    display: flex;
    align-items: flex-start;
    gap: var(--space-small);
    padding: var(--space-normal);
    margin-bottom: var(--space-small);
    background: var(--s-25);
    border-radius: var(--border-radius-normal);
    position: relative;
    padding-left: var(--space-large);

    &::before {
      content: counter(step-counter);
      counter-increment: step-counter;
      position: absolute;
      left: var(--space-small);
      top: var(--space-normal);
      width: 24px;
      height: 24px;
      background: var(--w-500);
      color: white;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: var(--font-size-mini);
      font-weight: var(--font-weight-bold);
    }

    span {
      flex: 1;
      font-size: var(--font-size-small);
      color: var(--s-700);
      line-height: 1.5;
    }
  }
}

.limitations-list {
  list-style: none;
  padding: 0;
  margin: 0;

  li {
    display: flex;
    align-items: flex-start;
    gap: var(--space-small);
    padding: var(--space-small) 0;
    font-size: var(--font-size-small);
    color: var(--s-700);
    line-height: 1.5;
  }
}
</style>
