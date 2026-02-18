<script>
import timeMixin from 'dashboard/mixins/time';
import AudioPlayer from 'shared/components/AudioPlayer.vue';
import QualityIndicator from './QualityIndicator.vue';

export default {
  name: 'CallDetailsModal',
  components: {
    AudioPlayer,
    QualityIndicator,
  },
  mixins: [timeMixin],
  props: {
    call: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      showTechnicalInfo: false,
    };
  },
  computed: {
    hasQualityMetrics() {
      return (
        this.call.quality_metrics &&
        Object.keys(this.call.quality_metrics).length > 0
      );
    },
  },
  methods: {
    getCallIcon() {
      if (this.call.direction === 'inbound') {
        return this.call.status === 'ended' ? 'call-inbound' : 'call-missed';
      }
      return this.call.status === 'ended' ? 'call-outbound' : 'call-end';
    },
    getStatusTitle() {
      const statusTitles = {
        ended: this.$t('WHATSAPP_CALLS.STATUS_TITLE.COMPLETED'),
        rejected: this.$t('WHATSAPP_CALLS.STATUS_TITLE.REJECTED'),
        failed: this.$t('WHATSAPP_CALLS.STATUS_TITLE.FAILED'),
      };
      return statusTitles[this.call.status] || this.call.status;
    },
    getStatusSubtitle() {
      if (this.call.duration) {
        return this.$t('WHATSAPP_CALLS.CALL_LASTED', {
          duration: this.call.duration,
        });
      }
      return this.$t('WHATSAPP_CALLS.CALL_NOT_CONNECTED');
    },
    getDirectionText() {
      return this.call.direction === 'inbound'
        ? this.$t('WHATSAPP_CALLS.INBOUND_CALL')
        : this.$t('WHATSAPP_CALLS.OUTBOUND_CALL');
    },
    getStatusText() {
      const statusMap = {
        ended: this.$t('WHATSAPP_CALLS.STATUS.COMPLETED'),
        rejected: this.$t('WHATSAPP_CALLS.STATUS.REJECTED'),
        failed: this.$t('WHATSAPP_CALLS.STATUS.FAILED'),
      };
      return statusMap[this.call.status] || this.call.status;
    },
    formatDateTime(timestamp) {
      return this.dynamicTime(timestamp);
    },
    formatFullDateTime(timestamp) {
      const date = new Date(timestamp);
      return date.toLocaleString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
      });
    },
    toggleTechnicalInfo() {
      this.showTechnicalInfo = !this.showTechnicalInfo;
    },
    downloadRecording() {
      const link = document.createElement('a');
      link.href = this.call.recording_url;
      link.download = `call-${this.call.id}.mp3`;
      link.click();
    },
  },
};
</script>

<template>
  <div class="call-details-modal">
    <woot-modal-header
      :header-title="$t('WHATSAPP_CALLS.CALL_DETAILS')"
      :header-content="formatDateTime(call.initiated_at)"
    />

    <div class="modal-content">
      <!-- Call Status Overview -->
      <div class="detail-section">
        <div class="status-overview">
          <fluent-icon
            :icon="getCallIcon()"
            size="48"
            :class="`status-${call.status}`"
          />
          <h3 class="status-title">
            {{ getStatusTitle() }}
          </h3>
          <p class="status-subtitle">
            {{ getStatusSubtitle() }}
          </p>
        </div>
      </div>

      <!-- Call Information -->
      <div class="detail-section">
        <h4 class="section-title">
          {{ $t('WHATSAPP_CALLS.CALL_INFORMATION') }}
        </h4>

        <div class="detail-grid">
          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.DIRECTION') }}</span>
            <span class="value">{{ getDirectionText() }}</span>
          </div>

          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.STATUS') }}</span>
            <span class="value" :class="`status-${call.status}`">
              {{ getStatusText() }}
            </span>
          </div>

          <div v-if="call.duration" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.DURATION') }}</span>
            <span class="value">{{ call.duration }}</span>
          </div>

          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.INITIATED_AT') }}</span>
            <span class="value">{{
              formatFullDateTime(call.initiated_at)
            }}</span>
          </div>

          <div v-if="call.answered_at" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.ANSWERED_AT') }}</span>
            <span class="value">{{
              formatFullDateTime(call.answered_at)
            }}</span>
          </div>

          <div v-if="call.ended_at" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.ENDED_AT') }}</span>
            <span class="value">{{ formatFullDateTime(call.ended_at) }}</span>
          </div>

          <div v-if="call.end_reason" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.END_REASON') }}</span>
            <span class="value">{{ call.end_reason }}</span>
          </div>
        </div>
      </div>

      <!-- Contact Information -->
      <div class="detail-section">
        <h4 class="section-title">
          {{ $t('WHATSAPP_CALLS.CONTACT_INFORMATION') }}
        </h4>

        <div class="detail-grid">
          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.CONTACT_NAME') }}</span>
            <span class="value">{{ call.contact_name || '-' }}</span>
          </div>

          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.PHONE_NUMBER') }}</span>
            <span class="value">{{ call.contact_number }}</span>
          </div>
        </div>
      </div>

      <!-- Call Quality Metrics -->
      <div v-if="hasQualityMetrics" class="detail-section">
        <h4 class="section-title">
          {{ $t('WHATSAPP_CALLS.CALL_QUALITY') }}
        </h4>

        <div class="detail-grid">
          <div v-if="call.quality_metrics.audio_quality" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.AUDIO_QUALITY') }}</span>
            <span class="value">
              <QualityIndicator :quality="call.quality_metrics.audio_quality" />
            </span>
          </div>

          <div v-if="call.quality_metrics.packet_loss" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.PACKET_LOSS') }}</span>
            <span class="value">{{ call.quality_metrics.packet_loss }}%</span>
          </div>

          <div v-if="call.quality_metrics.jitter" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.JITTER') }}</span>
            <span class="value">{{ call.quality_metrics.jitter }}ms</span>
          </div>

          <div v-if="call.quality_metrics.latency" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.LATENCY') }}</span>
            <span class="value">{{ call.quality_metrics.latency }}ms</span>
          </div>
        </div>
      </div>

      <!-- Recording -->
      <div v-if="call.recording_url" class="detail-section">
        <h4 class="section-title">
          {{ $t('WHATSAPP_CALLS.RECORDING') }}
        </h4>

        <AudioPlayer
          :src="call.recording_url"
          :download-filename="`call-${call.id}.mp3`"
        />
      </div>

      <!-- Technical Information -->
      <div v-if="showTechnicalInfo" class="detail-section">
        <h4 class="section-title">
          {{ $t('WHATSAPP_CALLS.TECHNICAL_INFO') }}
        </h4>

        <div class="detail-grid">
          <div class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.CALL_ID') }}</span>
            <span class="value monospace">{{ call.id }}</span>
          </div>

          <div v-if="call.whatsapp_call_id" class="detail-item">
            <span class="label">{{
              $t('WHATSAPP_CALLS.WHATSAPP_CALL_ID')
            }}</span>
            <span class="value monospace">{{ call.whatsapp_call_id }}</span>
          </div>

          <div v-if="call.media_server_session_id" class="detail-item">
            <span class="label">{{ $t('WHATSAPP_CALLS.SESSION_ID') }}</span>
            <span class="value monospace">{{
              call.media_server_session_id
            }}</span>
          </div>
        </div>
      </div>
    </div>

    <div class="modal-footer">
      <woot-button variant="clear" @click="$emit('close')">
        {{ $t('WHATSAPP_CALLS.CLOSE') }}
      </woot-button>

      <woot-button
        v-if="call.recording_url"
        icon="arrow-download"
        @click="downloadRecording"
      >
        {{ $t('WHATSAPP_CALLS.DOWNLOAD_RECORDING') }}
      </woot-button>

      <woot-button
        icon="more-vertical"
        variant="clear"
        @click="toggleTechnicalInfo"
      >
        {{
          showTechnicalInfo
            ? $t('WHATSAPP_CALLS.HIDE_TECHNICAL')
            : $t('WHATSAPP_CALLS.SHOW_TECHNICAL')
        }}
      </woot-button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.call-details-modal {
  .modal-content {
    padding: var(--space-normal);
    max-height: 70vh;
    overflow-y: auto;
  }

  .detail-section {
    margin-bottom: var(--space-large);

    &:last-child {
      margin-bottom: 0;
    }
  }

  .status-overview {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: var(--space-large) 0;

    .status-ended {
      color: var(--g-600);
    }

    .status-rejected,
    .status-failed {
      color: var(--r-500);
    }

    .status-title {
      margin: var(--space-small) 0 var(--space-micro);
      font-size: var(--font-size-large);
      font-weight: var(--font-weight-bold);
      color: var(--s-900);
    }

    .status-subtitle {
      margin: 0;
      font-size: var(--font-size-small);
      color: var(--s-600);
    }
  }

  .section-title {
    margin: 0 0 var(--space-normal);
    font-size: var(--font-size-medium);
    font-weight: var(--font-weight-medium);
    color: var(--s-900);
  }

  .detail-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: var(--space-normal);
  }

  .detail-item {
    display: flex;
    flex-direction: column;
    gap: var(--space-micro);

    .label {
      font-size: var(--font-size-mini);
      font-weight: var(--font-weight-medium);
      color: var(--s-600);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .value {
      font-size: var(--font-size-small);
      color: var(--s-900);

      &.monospace {
        font-family: monospace;
        font-size: var(--font-size-mini);
      }

      &.status-ended {
        color: var(--g-700);
      }

      &.status-rejected,
      &.status-failed {
        color: var(--r-700);
      }
    }
  }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-small);
    padding: var(--space-normal);
    border-top: 1px solid var(--s-100);
  }
}
</style>
