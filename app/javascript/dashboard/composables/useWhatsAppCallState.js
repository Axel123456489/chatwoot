// Frontend composable for managing WhatsApp call state
// Centralizes call state logic and reduces code duplication

import { ref, computed } from 'vue';

export function useWhatsAppCallState() {
  const callId = ref(null);
  const status = ref('idle');
  const duration = ref(0);
  const error = ref(null);
  const callQuality = ref(null);

  // Computed properties
  const isActive = computed(() =>
    ['connecting', 'ringing', 'accepted', 'connected', 'holding'].includes(
      status.value
    )
  );

  const isEnded = computed(() =>
    ['ended', 'failed', 'rejected', 'timeout', 'cancelled'].includes(
      status.value
    )
  );

  const canTerminate = computed(() => isActive.value);

  const canMute = computed(() =>
    ['connected', 'holding'].includes(status.value)
  );

  const statusLabel = computed(() => {
    const labels = {
      idle: 'Inactivo',
      connecting: 'Conectando...',
      ringing: 'Llamando...',
      accepted: 'Aceptada',
      connected: 'En llamada',
      holding: 'En espera',
      ended: 'Finalizada',
      failed: 'Fallida',
      rejected: 'Rechazada',
      timeout: 'Sin respuesta',
      cancelled: 'Cancelada',
    };
    return labels[status.value] || status.value;
  });

  const statusColor = computed(() => {
    const colors = {
      connecting: 'warning',
      ringing: 'warning',
      accepted: 'success',
      connected: 'success',
      holding: 'secondary',
      ended: 'secondary',
      failed: 'alert',
      rejected: 'alert',
      timeout: 'alert',
      cancelled: 'secondary',
    };
    return colors[status.value] || 'secondary';
  });

  const durationFormatted = computed(() => {
    if (!duration.value) return '00:00';

    const minutes = Math.floor(duration.value / 60);
    const seconds = duration.value % 60;
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  });

  // Methods
  function updateStatus(newStatus) {
    status.value = newStatus;
  }

  function setCallId(id) {
    callId.value = id;
  }

  function incrementDuration() {
    if (status.value === 'connected') {
      duration.value += 1;
    }
  }

  function setError(errorMessage) {
    error.value = errorMessage;
  }

  function clearError() {
    error.value = null;
  }

  function setQuality(qualityData) {
    callQuality.value = qualityData;
  }

  function reset() {
    callId.value = null;
    status.value = 'idle';
    duration.value = 0;
    error.value = null;
    callQuality.value = null;
  }

  return {
    // State
    callId,
    status,
    duration,
    error,
    callQuality,

    // Computed
    isActive,
    isEnded,
    canTerminate,
    canMute,
    statusLabel,
    statusColor,
    durationFormatted,

    // Methods
    updateStatus,
    setCallId,
    incrementDuration,
    setError,
    clearError,
    setQuality,
    reset,
  };
}
