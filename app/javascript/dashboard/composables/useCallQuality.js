import { ref, computed, onUnmounted } from 'vue';

/**
 * Composable for monitoring and managing WebRTC call quality
 *
 * Features:
 * - Connection quality monitoring (latency, jitter, packet loss)
 * - Adaptive bitrate adjustment
 * - Network condition detection
 * - Audio quality optimization
 * - Echo cancellation and noise suppression
 * - Connection recovery and reconnection logic
 *
 * @returns {Object} Call quality monitoring and control methods
 */
export default function useCallQuality() {
  // Quality Metrics
  const latency = ref(0);
  const jitter = ref(0);
  const packetLoss = ref(0);
  const bandwidth = ref({ upload: 0, download: 0 });
  const audioLevel = ref(0);

  // Quality State
  const connectionQuality = ref('unknown'); // excellent, good, fair, poor, bad
  const isMonitoring = ref(false);
  const lastStatsTimestamp = ref(0);

  // Media Constraints
  const mediaConstraints = ref({
    audio: {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      sampleRate: 48000,
      channelCount: 1,
    },
    video: false,
  });

  // Reconnection State
  const reconnectionAttempts = ref(0);
  const maxReconnectionAttempts = 5;
  const isReconnecting = ref(false);

  // Stats Collection
  let peerConnection = null;
  let statsInterval = null;
  let previousStats = null;

  /**
   * Computed: Overall call quality rating
   */
  const qualityRating = computed(() => {
    if (packetLoss.value > 5) return 'bad';
    if (packetLoss.value > 3 || latency.value > 300) return 'poor';
    if (packetLoss.value > 1 || latency.value > 200) return 'fair';
    if (latency.value > 100) return 'good';
    return 'excellent';
  });

  /**
   * Computed: Quality as percentage (0-100)
   */
  const qualityPercentage = computed(() => {
    const ratings = {
      excellent: 100,
      good: 80,
      fair: 60,
      poor: 40,
      bad: 20,
      unknown: 0,
    };
    return ratings[qualityRating.value] || 0;
  });

  /**
   * Computed: Network condition
   */
  const networkCondition = computed(() => {
    if (bandwidth.value.download > 500) return 'excellent';
    if (bandwidth.value.download > 300) return 'good';
    if (bandwidth.value.download > 150) return 'fair';
    if (bandwidth.value.download > 50) return 'poor';
    return 'bad';
  });

  /**
   * Computed: Should show quality warning
   */
  const shouldShowQualityWarning = computed(() => {
    return ['poor', 'bad'].includes(qualityRating.value);
  });

  /**
   * Computed: Quality warning message
   */
  const qualityWarningMessage = computed(() => {
    if (qualityRating.value === 'bad') {
      return 'La calidad de la llamada es muy baja. Verifica tu conexión.';
    }
    if (qualityRating.value === 'poor') {
      return 'La calidad de la llamada es baja. Puede haber interrupciones.';
    }
    return '';
  });

  /**
   * Initialize quality monitoring for a peer connection
   *
   * @param {RTCPeerConnection} pc - WebRTC peer connection
   */
  function startMonitoring(pc) {
    if (!pc) {
      console.warn('Cannot start monitoring: no peer connection provided');
      return;
    }

    peerConnection = pc;
    isMonitoring.value = true;
    previousStats = null;

    // Collect stats every second
    statsInterval = setInterval(async () => {
      await collectStats();
    }, 1000);
  }

  /**
   * Stop quality monitoring
   */
  function stopMonitoring() {
    if (statsInterval) {
      clearInterval(statsInterval);
      statsInterval = null;
    }

    isMonitoring.value = false;
    peerConnection = null;
    previousStats = null;

    // Reset metrics
    resetMetrics();
  }

  /**
   * Collect WebRTC stats from peer connection
   */
  async function collectStats() {
    if (!peerConnection) return;

    try {
      const stats = await peerConnection.getStats();
      const timestamp = Date.now();

      stats.forEach(report => {
        // Inbound RTP (receiving audio)
        if (report.type === 'inbound-rtp' && report.mediaType === 'audio') {
          processInboundStats(report, timestamp);
        }

        // Outbound RTP (sending audio)
        if (report.type === 'outbound-rtp' && report.mediaType === 'audio') {
          processOutboundStats(report, timestamp);
        }

        // Candidate pair (connection stats)
        if (report.type === 'candidate-pair' && report.state === 'succeeded') {
          processCandidatePairStats(report);
        }

        // Media source (audio level)
        if (report.type === 'media-source' && report.kind === 'audio') {
          audioLevel.value = report.audioLevel || 0;
        }
      });

      lastStatsTimestamp.value = timestamp;
      connectionQuality.value = qualityRating.value;

      // Auto-adjust quality if needed
      if (shouldShowQualityWarning.value) {
        await adjustQualitySettings();
      }
    } catch (error) {
      console.error('Failed to collect stats:', error);
    }
  }

  /**
   * Process inbound RTP statistics
   */
  function processInboundStats(report, timestamp) {
    if (!previousStats || !previousStats.inbound) {
      previousStats = { ...previousStats, inbound: report };
      return;
    }

    const prev = previousStats.inbound;
    const timeDiff = (timestamp - lastStatsTimestamp.value) / 1000; // seconds

    // Calculate packet loss
    const packetsReceived = report.packetsReceived - prev.packetsReceived;
    const packetsLost = report.packetsLost - prev.packetsLost;

    if (packetsReceived > 0) {
      const lossPercentage =
        (packetsLost / (packetsReceived + packetsLost)) * 100;
      packetLoss.value = Math.max(0, lossPercentage);
    }

    // Calculate jitter (in milliseconds)
    if (report.jitter !== undefined) {
      jitter.value = report.jitter * 1000;
    }

    // Estimate bandwidth
    const bytesReceived = report.bytesReceived - prev.bytesReceived;
    bandwidth.value.download = Math.round(
      (bytesReceived * 8) / timeDiff / 1000
    ); // kbps

    previousStats.inbound = report;
  }

  /**
   * Process outbound RTP statistics
   */
  function processOutboundStats(report, timestamp) {
    if (!previousStats || !previousStats.outbound) {
      previousStats = { ...previousStats, outbound: report };
      return;
    }

    const prev = previousStats.outbound;
    const timeDiff = (timestamp - lastStatsTimestamp.value) / 1000;

    // Estimate upload bandwidth
    const bytesSent = report.bytesSent - prev.bytesSent;
    bandwidth.value.upload = Math.round((bytesSent * 8) / timeDiff / 1000); // kbps

    previousStats.outbound = report;
  }

  /**
   * Process candidate pair statistics (RTT/latency)
   */
  function processCandidatePairStats(report) {
    if (report.currentRoundTripTime !== undefined) {
      latency.value = Math.round(report.currentRoundTripTime * 1000); // milliseconds
    }
  }

  /**
   * Adjust quality settings based on network conditions
   */
  async function adjustQualitySettings() {
    if (!peerConnection) return;

    try {
      const senders = peerConnection.getSenders();
      const audioSender = senders.find(
        sender => sender.track?.kind === 'audio'
      );

      if (!audioSender) return;

      const parameters = audioSender.getParameters();

      if (!parameters.encodings || parameters.encodings.length === 0) {
        parameters.encodings = [{}];
      }

      // Adjust bitrate based on quality
      if (qualityRating.value === 'bad') {
        // Reduce to minimum bitrate
        parameters.encodings[0].maxBitrate = 16000; // 16 kbps
      } else if (qualityRating.value === 'poor') {
        // Moderate bitrate
        parameters.encodings[0].maxBitrate = 32000; // 32 kbps
      } else {
        // Full quality
        parameters.encodings[0].maxBitrate = 64000; // 64 kbps
      }

      await audioSender.setParameters(parameters);
      console.log(
        'Adjusted audio bitrate:',
        parameters.encodings[0].maxBitrate
      );
    } catch (error) {
      console.error('Failed to adjust quality settings:', error);
    }
  }

  /**
   * Apply echo cancellation settings
   *
   * @param {boolean} enabled - Enable/disable echo cancellation
   */
  function setEchoCancellation(enabled) {
    mediaConstraints.value.audio.echoCancellation = enabled;
    console.log('Echo cancellation:', enabled ? 'enabled' : 'disabled');
  }

  /**
   * Apply noise suppression settings
   *
   * @param {boolean} enabled - Enable/disable noise suppression
   */
  function setNoiseSuppression(enabled) {
    mediaConstraints.value.audio.noiseSuppression = enabled;
    console.log('Noise suppression:', enabled ? 'enabled' : 'disabled');
  }

  /**
   * Apply auto gain control settings
   *
   * @param {boolean} enabled - Enable/disable auto gain control
   */
  function setAutoGainControl(enabled) {
    mediaConstraints.value.audio.autoGainControl = enabled;
    console.log('Auto gain control:', enabled ? 'enabled' : 'disabled');
  }

  /**
   * Get optimized media constraints based on network conditions
   *
   * @returns {Object} Media constraints
   */
  function getOptimizedConstraints() {
    const constraints = { ...mediaConstraints.value };

    // Adjust sample rate based on network
    if (networkCondition.value === 'poor' || networkCondition.value === 'bad') {
      constraints.audio.sampleRate = 24000; // Lower quality for poor network
    }

    return constraints;
  }

  /**
   * Attempt to reconnect peer connection
   *
   * @param {Function} reconnectCallback - Callback to execute reconnection
   */
  async function attemptReconnection(reconnectCallback) {
    if (reconnectionAttempts.value >= maxReconnectionAttempts) {
      console.error('Max reconnection attempts reached');
      isReconnecting.value = false;
      return false;
    }

    isReconnecting.value = true;
    reconnectionAttempts.value += 1;

    try {
      console.log(
        `Reconnection attempt ${reconnectionAttempts.value}/${maxReconnectionAttempts}`
      );

      // Exponential backoff
      const delay = Math.min(
        1000 * 2 ** (reconnectionAttempts.value - 1),
        10000
      );
      await new Promise(resolve => {
        setTimeout(resolve, delay);
      });

      // Execute reconnection callback
      if (reconnectCallback && typeof reconnectCallback === 'function') {
        await reconnectCallback();
      }

      isReconnecting.value = false;
      reconnectionAttempts.value = 0; // Reset on success
      return true;
    } catch (error) {
      console.error('Reconnection failed:', error);
      isReconnecting.value = false;
      return false;
    }
  }

  /**
   * Reset connection metrics
   */
  function resetMetrics() {
    latency.value = 0;
    jitter.value = 0;
    packetLoss.value = 0;
    bandwidth.value = { upload: 0, download: 0 };
    audioLevel.value = 0;
    connectionQuality.value = 'unknown';
    reconnectionAttempts.value = 0;
  }

  /**
   * Get current quality metrics as object
   *
   * @returns {Object} Quality metrics
   */
  function getQualityMetrics() {
    return {
      latency: latency.value,
      jitter: jitter.value,
      packetLoss: packetLoss.value,
      bandwidth: { ...bandwidth.value },
      audioLevel: audioLevel.value,
      quality: connectionQuality.value,
      rating: qualityRating.value,
      percentage: qualityPercentage.value,
      networkCondition: networkCondition.value,
    };
  }

  // Cleanup on unmount
  onUnmounted(() => {
    stopMonitoring();
  });

  return {
    // State
    latency,
    jitter,
    packetLoss,
    bandwidth,
    audioLevel,
    connectionQuality,
    isMonitoring,
    isReconnecting,
    reconnectionAttempts,

    // Computed
    qualityRating,
    qualityPercentage,
    networkCondition,
    shouldShowQualityWarning,
    qualityWarningMessage,

    // Methods
    startMonitoring,
    stopMonitoring,
    setEchoCancellation,
    setNoiseSuppression,
    setAutoGainControl,
    getOptimizedConstraints,
    attemptReconnection,
    resetMetrics,
    getQualityMetrics,

    // Constraints
    mediaConstraints,
  };
}
