<script>
export default {
  name: 'QualityIndicator',
  props: {
    quality: {
      type: [String, Number],
      required: true,
    },
  },
  computed: {
    qualityLevel() {
      if (typeof this.quality === 'number') {
        if (this.quality >= 4.5) return 'excellent';
        if (this.quality >= 4) return 'good';
        if (this.quality >= 3) return 'fair';
        if (this.quality >= 2) return 'poor';
        return 'bad';
      }
      return this.quality.toLowerCase();
    },
    activeBarCount() {
      const levels = {
        excellent: 5,
        good: 4,
        fair: 3,
        poor: 2,
        bad: 1,
      };
      return levels[this.qualityLevel] || 0;
    },
    qualityText() {
      const texts = {
        excellent: this.$t('WHATSAPP_CALLS.QUALITY.EXCELLENT'),
        good: this.$t('WHATSAPP_CALLS.QUALITY.GOOD'),
        fair: this.$t('WHATSAPP_CALLS.QUALITY.FAIR'),
        poor: this.$t('WHATSAPP_CALLS.QUALITY.POOR'),
        bad: this.$t('WHATSAPP_CALLS.QUALITY.BAD'),
      };
      return (
        texts[this.qualityLevel] || this.$t('WHATSAPP_CALLS.QUALITY.UNKNOWN')
      );
    },
  },
};
</script>

<template>
  <div class="quality-indicator">
    <div class="quality-bars">
      <div
        v-for="bar in 5"
        :key="bar"
        class="bar"
        :class="{ active: bar <= activeBarCount }"
      />
    </div>
    <span class="quality-text">{{ qualityText }}</span>
  </div>
</template>

<style lang="scss" scoped>
.quality-indicator {
  display: inline-flex;
  align-items: center;
  gap: var(--space-small);

  .quality-bars {
    display: flex;
    align-items: flex-end;
    gap: 2px;
    height: 16px;

    .bar {
      width: 4px;
      background: var(--s-200);
      border-radius: 2px;
      transition: all 0.2s ease;

      &:nth-child(1) {
        height: 20%;
      }
      &:nth-child(2) {
        height: 40%;
      }
      &:nth-child(3) {
        height: 60%;
      }
      &:nth-child(4) {
        height: 80%;
      }
      &:nth-child(5) {
        height: 100%;
      }

      &.active {
        background: var(--g-500);
      }
    }
  }

  .quality-text {
    font-size: var(--font-size-mini);
    font-weight: var(--font-weight-medium);
    color: var(--s-700);
  }
}
</style>
