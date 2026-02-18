<script>
import { mapGetters } from 'vuex';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ModalHeader from 'dashboard/components/ModalHeader.vue';
import WhatsappCallsAPI from 'dashboard/api/whatsapp/calls';
import {
  getErrorDetails,
  isRetryableError,
  logError,
} from 'dashboard/helper/whatsappCallErrors';

export default {
  name: 'WhatsAppCallButton',
  components: {
    Avatar,
    ModalHeader,
  },
  props: {
    conversation: {
      type: Object,
      required: true,
    },
    contact: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      showPermissionModal: false,
      showConfirmModal: false,
      isInitiatingCall: false,
      isRequestingPermission: false,
      callPermission: null,
      remainingCalls: null,
      dailyLimit: 10,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
      uiFlags: 'inboxes/getUIFlags',
    }),
    inbox() {
      return this.conversation.inbox;
    },
    isWhatsAppChannel() {
      return this.inbox?.channel_type === 'Channel::Whatsapp';
    },
    callingEnabled() {
      return this.inbox?.additional_attributes?.calling_enabled === true;
    },
    canMakeCalls() {
      return this.isWhatsAppChannel && this.callingEnabled;
    },
    hasActiveCall() {
      const callStatus = this.conversation.additional_attributes?.call_status;
      return [
        'ringing',
        'accepted',
        'connecting',
        'connected',
        'holding',
      ].includes(callStatus);
    },
    hasPermission() {
      return this.callPermission?.permission_status === 'granted';
    },
    canCallNow() {
      return (
        this.hasPermission &&
        (this.remainingCalls === null || this.remainingCalls > 0)
      );
    },
    isDisabled() {
      return this.hasActiveCall || this.isInitiatingCall;
    },
    buttonIcon() {
      if (this.hasActiveCall) return 'call-checkmark';
      if (this.hasPermission) return 'call';
      return 'call-add';
    },
    buttonText() {
      if (this.hasActiveCall) return this.$t('WHATSAPP_CALLS.IN_CALL');
      if (this.hasPermission) return this.$t('WHATSAPP_CALLS.CALL');
      return this.$t('WHATSAPP_CALLS.REQUEST_CALL');
    },
    buttonColorScheme() {
      if (this.hasActiveCall) return 'success';
      if (this.hasPermission) return 'primary';
      return 'secondary';
    },
    buttonTooltip() {
      if (this.hasActiveCall) return this.$t('WHATSAPP_CALLS.CALL_IN_PROGRESS');
      if (!this.hasPermission)
        return this.$t('WHATSAPP_CALLS.PERMISSION_REQUIRED_TOOLTIP');
      if (this.remainingCalls === 0)
        return this.$t('WHATSAPP_CALLS.DAILY_LIMIT_REACHED');
      return this.$t('WHATSAPP_CALLS.START_WHATSAPP_CALL');
    },
    confirmModalContent() {
      return this.$t('WHATSAPP_CALLS.CONFIRM_CALL_TO', {
        name: this.contact.name,
      });
    },
  },
  mounted() {
    this.fetchCallPermission();
  },
  methods: {
    async fetchCallPermission() {
      try {
        const response = await WhatsappCallsAPI.getPermission({
          accountId: this.conversation.account_id,
          contactId: this.contact.id,
          inboxId: this.inbox.id,
        });

        this.callPermission = response.data;
        this.remainingCalls = response.data.remaining_calls;
      } catch (error) {
        console.error('Failed to fetch call permission:', error);
      }
    },
    handleCallClick() {
      if (this.hasActiveCall) {
        // Do nothing if call is already active
        return;
      }

      if (!this.hasPermission) {
        this.showPermissionModal = true;
      } else if (this.canCallNow) {
        this.showConfirmModal = true;
      } else {
        this.showAlert(this.$t('WHATSAPP_CALLS.CANNOT_CALL_NOW'));
      }
    },
    async requestPermission() {
      this.isRequestingPermission = true;

      try {
        const response = await WhatsappCallsAPI.requestPermission({
          accountId: this.conversation.account_id,
          contactId: this.contact.id,
          inboxId: this.inbox.id,
        });

        this.callPermission = response.data;
        this.showAlert(this.$t('WHATSAPP_CALLS.PERMISSION_REQUESTED'));
        this.closePermissionModal();
      } catch (error) {
        this.showAlert(this.$t('WHATSAPP_CALLS.PERMISSION_REQUEST_FAILED'));
        console.error('Failed to request permission:', error);
      } finally {
        this.isRequestingPermission = false;
      }
    },
    async initiateCall() {
      this.isInitiatingCall = true;

      try {
        const response = await WhatsappCallsAPI.initiateCall({
          accountId: this.conversation.account_id,
          conversationId: this.conversation.id,
          inboxId: this.inbox.id,
        });

        this.remainingCalls = response.data.remaining_calls;
        this.showAlert(this.$t('WHATSAPP_CALLS.CALL_INITIATED'));
        this.closeConfirmModal();

        // Emit event for parent to show call control panel
        this.$emit('call-initiated', {
          callId: response.data.call_id,
          conversationId: this.conversation.id,
        });
      } catch (error) {
        logError('Call Initiation', error);
        const errorDetails = getErrorDetails(error);

        this.showAlert(errorDetails.message);

        // Show retry option if error is retryable
        if (isRetryableError(error)) {
          console.info('Call failed with retryable error. Retry is possible.');
        }
      } finally {
        this.isInitiatingCall = false;
      }
    },
    closePermissionModal() {
      this.showPermissionModal = false;
    },
    closeConfirmModal() {
      this.showConfirmModal = false;
    },
  },
};
</script>

<template>
  <div class="whatsapp-call-button-wrapper">
    <woot-button
      v-if="canMakeCalls"
      v-tooltip.left="buttonTooltip"
      :color-scheme="buttonColorScheme"
      :icon="buttonIcon"
      :is-loading="isInitiatingCall"
      :disabled="isDisabled"
      size="small"
      variant="smooth"
      @click="handleCallClick"
    >
      {{ buttonText }}
    </woot-button>

    <!-- Permission Request Modal -->
    <woot-modal
      v-model:show="showPermissionModal"
      :on-close="closePermissionModal"
    >
      <ModalHeader
        :header-title="$t('WHATSAPP_CALLS.REQUEST_PERMISSION')"
        :header-content="$t('WHATSAPP_CALLS.PERMISSION_REQUIRED_DESC')"
      />

      <div class="permission-modal-body">
        <p>{{ $t('WHATSAPP_CALLS.PERMISSION_EXPLANATION') }}</p>

        <div class="permission-info">
          <fluent-icon icon="info" size="16" />
          <span>{{
            $t('WHATSAPP_CALLS.DAILY_LIMIT_INFO', { limit: dailyLimit })
          }}</span>
        </div>

        <div class="modal-footer">
          <woot-button variant="clear" @click="closePermissionModal">
            {{ $t('WHATSAPP_CALLS.CANCEL') }}
          </woot-button>
          <woot-button
            color-scheme="primary"
            :is-loading="isRequestingPermission"
            @click="requestPermission"
          >
            {{ $t('WHATSAPP_CALLS.SEND_REQUEST') }}
          </woot-button>
        </div>
      </div>
    </woot-modal>

    <!-- Confirm Call Modal -->
    <woot-modal v-model:show="showConfirmModal" :on-close="closeConfirmModal">
      <ModalHeader
        :header-title="$t('WHATSAPP_CALLS.CONFIRM_CALL')"
        :header-content="confirmModalContent"
      />

      <div class="confirm-modal-body">
        <div class="contact-info">
          <Avatar :src="contact.thumbnail" :name="contact.name" :size="48" />
          <div class="contact-details">
            <h4>{{ contact.name }}</h4>
            <p>{{ contact.phone_number }}</p>
          </div>
        </div>

        <div v-if="remainingCalls !== null" class="remaining-calls-info">
          <fluent-icon icon="call" size="16" />
          <span>
            {{
              $t('WHATSAPP_CALLS.REMAINING_CALLS', { count: remainingCalls })
            }}
          </span>
        </div>

        <div class="modal-footer">
          <woot-button variant="clear" @click="closeConfirmModal">
            {{ $t('WHATSAPP_CALLS.CANCEL') }}
          </woot-button>
          <woot-button
            color-scheme="success"
            icon="call"
            :is-loading="isInitiatingCall"
            @click="initiateCall"
          >
            {{ $t('WHATSAPP_CALLS.START_CALL') }}
          </woot-button>
        </div>
      </div>
    </woot-modal>
  </div>
</template>

<style lang="scss" scoped>
.whatsapp-call-button-wrapper {
  display: inline-block;
}

.permission-modal-body,
.confirm-modal-body {
  padding: var(--space-normal);

  p {
    margin: 0 0 var(--space-normal);
    color: var(--s-700);
    line-height: 1.5;
  }

  .permission-info {
    display: flex;
    align-items: flex-start;
    gap: var(--space-small);
    padding: var(--space-small);
    background: var(--b-50);
    border-radius: var(--border-radius-normal);
    margin-bottom: var(--space-normal);
    font-size: var(--font-size-small);
    color: var(--s-700);

    .fluent-icon {
      color: var(--b-500);
      flex-shrink: 0;
      margin-top: 2px;
    }
  }

  .contact-info {
    display: flex;
    align-items: center;
    gap: var(--space-small);
    padding: var(--space-normal);
    background: var(--s-25);
    border-radius: var(--border-radius-normal);
    margin-bottom: var(--space-normal);

    .contact-details {
      flex: 1;

      h4 {
        margin: 0 0 var(--space-micro);
        font-size: var(--font-size-medium);
        font-weight: var(--font-weight-medium);
        color: var(--s-900);
      }

      p {
        margin: 0;
        font-size: var(--font-size-small);
        color: var(--s-600);
      }
    }
  }

  .remaining-calls-info {
    display: flex;
    align-items: center;
    gap: var(--space-small);
    padding: var(--space-small);
    background: var(--g-50);
    border-radius: var(--border-radius-normal);
    margin-bottom: var(--space-normal);
    font-size: var(--font-size-small);
    color: var(--g-700);
    font-weight: var(--font-weight-medium);

    .fluent-icon {
      color: var(--g-600);
    }
  }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-small);
    margin-top: var(--space-normal);
  }
}
</style>
