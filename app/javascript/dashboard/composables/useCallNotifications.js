import { ref, onMounted, onUnmounted } from 'vue';

/**
 * Composable for managing call-related browser notifications
 * Handles notification permissions, sound playback, and system notifications
 */
export const useCallNotifications = () => {
  const notificationPermission = ref(Notification.permission);
  const ringtoneAudio = ref(null);
  const notificationAudio = ref(null);
  const isRingtonePlaying = ref(false);

  /**
   * Request browser notification permission
   * @returns {Promise<String>} Permission state ('granted', 'denied', or 'default')
   */
  const requestNotificationPermission = async () => {
    if (!('Notification' in window)) {
      console.warn('This browser does not support notifications');
      return 'denied';
    }

    if (Notification.permission === 'granted') {
      return 'granted';
    }

    try {
      const permission = await Notification.requestPermission();
      notificationPermission.value = permission;
      return permission;
    } catch (error) {
      console.error('Error requesting notification permission:', error);
      return 'denied';
    }
  };

  /**
   * Show a system notification
   * @param {Object} options - Notification options
   * @param {String} options.title - Notification title
   * @param {String} options.body - Notification body text
   * @param {String} options.icon - Icon URL
   * @param {String} options.tag - Unique tag for notification
   * @param {Function} options.onClick - Click handler
   * @returns {Notification|null} Notification instance
   */
  const showNotification = ({ title, body, icon, tag, onClick }) => {
    if (!('Notification' in window)) {
      return null;
    }

    if (Notification.permission !== 'granted') {
      console.warn('Notification permission not granted');
      return null;
    }

    try {
      const notification = new Notification(title, {
        body,
        icon: icon || '/favicon.png',
        tag: tag || `call-${Date.now()}`,
        requireInteraction: true,
        silent: false,
      });

      if (onClick) {
        notification.onclick = () => {
          window.focus();
          onClick();
          notification.close();
        };
      }

      // Auto-close after 30 seconds
      setTimeout(() => {
        notification.close();
      }, 30000);

      return notification;
    } catch (error) {
      console.error('Error showing notification:', error);
      return null;
    }
  };

  /**
   * Show incoming call notification
   * @param {Object} call - Call data
   * @param {Function} onAccept - Accept callback
   * @param {Function} onReject - Reject callback
   * @returns {Notification|null}
   */
  const showIncomingCallNotification = (call, onAccept, onReject) => {
    const contactName = call.contact_name || call.contact_number || 'Unknown';

    const notification = showNotification({
      title: 'Incoming WhatsApp Call',
      body: `Call from ${contactName}`,
      icon: '/icons/whatsapp-call.png',
      tag: `incoming-call-${call.id}`,
      onClick: onAccept,
    });

    // Play notification sound
    playNotificationSound();

    return notification;
  };

  /**
   * Initialize audio elements
   */
  const initializeAudio = () => {
    if (!ringtoneAudio.value) {
      ringtoneAudio.value = new Audio('/audio/ringtone.mp3');
      ringtoneAudio.value.loop = true;
      ringtoneAudio.value.volume = 0.5;
    }

    if (!notificationAudio.value) {
      notificationAudio.value = new Audio('/audio/notification.mp3');
      notificationAudio.value.volume = 0.3;
    }
  };

  /**
   * Play ringtone (looped)
   * @returns {Promise<void>}
   */
  const playRingtone = async () => {
    initializeAudio();

    if (isRingtonePlaying.value) return;

    try {
      await ringtoneAudio.value.play();
      isRingtonePlaying.value = true;
    } catch (error) {
      console.warn('Failed to play ringtone:', error);
      // Browser may block autoplay, user interaction required
    }
  };

  /**
   * Stop ringtone
   */
  const stopRingtone = () => {
    if (!ringtoneAudio.value || !isRingtonePlaying.value) return;

    ringtoneAudio.value.pause();
    ringtoneAudio.value.currentTime = 0;
    isRingtonePlaying.value = false;
  };

  /**
   * Play notification sound (one-shot)
   * @returns {Promise<void>}
   */
  const playNotificationSound = async () => {
    initializeAudio();

    try {
      notificationAudio.value.currentTime = 0;
      await notificationAudio.value.play();
    } catch (error) {
      console.warn('Failed to play notification sound:', error);
    }
  };

  /**
   * Play call end sound
   * @returns {Promise<void>}
   */
  const playCallEndSound = async () => {
    const endSound = new Audio('/audio/call-end.mp3');
    endSound.volume = 0.4;

    try {
      await endSound.play();
    } catch (error) {
      console.warn('Failed to play call end sound:', error);
    }
  };

  /**
   * Play call connect sound
   * @returns {Promise<void>}
   */
  const playCallConnectSound = async () => {
    const connectSound = new Audio('/audio/call-connect.mp3');
    connectSound.volume = 0.3;

    try {
      await connectSound.play();
    } catch (error) {
      console.warn('Failed to play call connect sound:', error);
    }
  };

  /**
   * Show call ended notification
   * @param {Object} callData - Call information
   * @param {String} callData.duration - Call duration
   * @param {String} callData.endReason - Reason for call end
   */
  const showCallEndedNotification = ({ duration, endReason }) => {
    let message = 'Call ended';

    if (duration) {
      const minutes = Math.floor(duration / 60);
      const seconds = duration % 60;
      message = `Call ended - Duration: ${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    if (endReason && endReason !== 'completed') {
      message += ` (${endReason})`;
    }

    showNotification({
      title: 'WhatsApp Call',
      body: message,
      icon: '/icons/whatsapp-call.png',
      tag: 'call-ended',
    });

    playCallEndSound();
  };

  /**
   * Show call connected notification
   */
  const showCallConnectedNotification = () => {
    showNotification({
      title: 'WhatsApp Call',
      body: 'Call connected successfully',
      icon: '/icons/whatsapp-call.png',
      tag: 'call-connected',
    });

    playCallConnectSound();
  };

  /**
   * Show call failed notification
   * @param {String} errorMessage - Error message
   */
  const showCallFailedNotification = errorMessage => {
    showNotification({
      title: 'WhatsApp Call Failed',
      body: errorMessage || 'Failed to connect call',
      icon: '/icons/whatsapp-call-error.png',
      tag: 'call-failed',
    });
  };

  /**
   * Check if notifications are supported
   * @returns {Boolean}
   */
  const isNotificationSupported = () => {
    return 'Notification' in window;
  };

  /**
   * Check if notifications are granted
   * @returns {Boolean}
   */
  const isNotificationGranted = () => {
    return notificationPermission.value === 'granted';
  };

  // Initialize audio on mount
  onMounted(() => {
    initializeAudio();

    // Update permission state if it changes
    if ('Notification' in window) {
      notificationPermission.value = Notification.permission;
    }
  });

  // Cleanup on unmount
  onUnmounted(() => {
    stopRingtone();

    if (ringtoneAudio.value) {
      ringtoneAudio.value = null;
    }

    if (notificationAudio.value) {
      notificationAudio.value = null;
    }
  });

  return {
    // State
    notificationPermission,
    isRingtonePlaying,

    // Methods
    requestNotificationPermission,
    showNotification,
    showIncomingCallNotification,
    playRingtone,
    stopRingtone,
    playNotificationSound,
    playCallEndSound,
    playCallConnectSound,
    showCallEndedNotification,
    showCallConnectedNotification,
    showCallFailedNotification,
    isNotificationSupported,
    isNotificationGranted,
  };
};

export default useCallNotifications;
