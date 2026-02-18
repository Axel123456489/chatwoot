/* eslint-disable class-methods-use-this */
import BaseActionCableConnector from '../../../shared/helpers/BaseActionCableConnector';

class WhatsAppCallsActionCableConnector extends BaseActionCableConnector {
  constructor(app, accountId, userId) {
    super(app, accountId, userId);
    this.accountId = accountId;
    this.CancelTyping = [];
    this.events = {
      whatsapp_incoming_call: this.onIncomingCall,
      call_state_changed: this.onCallStateChanged,
      call_ended: this.onCallEnded,
    };
  }

  onIncomingCall = data => {
    const { call } = data;

    // Play notification sound
    this.playNotificationSound();

    // Show browser notification
    this.showBrowserNotification(call);

    // Add to incoming calls queue
    this.$store.dispatch('whatsappCalls/handleIncomingCall', call);

    // Show incoming call modal
    this.showIncomingCallNotification(call);
  };

  onCallStateChanged = data => {
    const { call_id, state, metadata } = data;

    // Update call state in store
    this.$store.dispatch('whatsappCalls/updateCallState', {
      callId: call_id,
      stateData: {
        status: state,
        ...metadata,
      },
    });

    // Handle specific state transitions
    this.handleStateTransition(call_id, state, metadata);
  };

  onCallEnded = data => {
    const { call_id, end_reason, duration, recording_url } = data;

    // Update call record
    this.$store.dispatch('whatsappCalls/updateCallState', {
      callId: call_id,
      stateData: {
        status: 'ended',
        end_reason,
        duration,
        recording_url,
        ended_at: new Date().toISOString(),
      },
    });

    // Clear active call if it matches
    const activeCall = this.$store.getters['whatsappCalls/getActiveCall'];
    if (activeCall && activeCall.id === call_id) {
      this.$store.dispatch('whatsappCalls/clearActiveCall');
    }

    // Show end notification
    this.showCallEndedNotification(end_reason, duration);
  };

  handleStateTransition(callId, state, metadata) {
    switch (state) {
      case 'ringing':
        this.playRingingTone();
        break;
      case 'connected':
        this.stopRingingTone();
        this.showCallConnectedToast();
        break;
      case 'failed':
        this.stopRingingTone();
        this.showCallFailedToast(metadata.error_message);
        break;
      case 'rejected':
        this.stopRingingTone();
        break;
      default:
        break;
    }
  }

  playNotificationSound = () => {
    try {
      const audio = new Audio('/audio/incoming-call.mp3');
      audio.volume = 0.5;
      audio.play().catch(() => undefined);
    } catch (error) {
      // noop
    }
  };

  playRingingTone = () => {
    if (this.ringingAudio) {
      return;
    }

    try {
      this.ringingAudio = new Audio('/audio/ringing.mp3');
      this.ringingAudio.loop = true;
      this.ringingAudio.volume = 0.3;
      this.ringingAudio.play().catch(() => undefined);
    } catch (error) {
      // noop
    }
  };

  stopRingingTone = () => {
    if (this.ringingAudio) {
      this.ringingAudio.pause();
      this.ringingAudio = null;
    }
  };

  showBrowserNotification = call => {
    if (!('Notification' in window)) {
      return;
    }

    if (Notification.permission === 'granted') {
      const notification = new Notification('Incoming WhatsApp Call', {
        body: `Call from ${call.contact_name || call.contact_number}`,
        icon: '/icons/call-icon.png',
        tag: `whatsapp-call-${call.id}`,
        requireInteraction: true,
      });

      notification.onclick = () => {
        window.focus();
        notification.close();
      };
    } else if (Notification.permission !== 'denied') {
      Notification.requestPermission();
    }
  };

  showIncomingCallNotification = call => {
    // Dispatch event to show incoming call modal
    window.dispatchEvent(
      new CustomEvent('show-incoming-call', {
        detail: { call },
      })
    );
  };

  showCallConnectedToast = () => {
    window.bus.$emit('newToastMessage', {
      message: 'Call connected successfully',
      type: 'success',
    });
  };

  showCallFailedToast = errorMessage => {
    window.bus.$emit('newToastMessage', {
      message: errorMessage || 'Call failed to connect',
      type: 'error',
    });
  };

  showCallEndedNotification = (reason, duration) => {
    let message = 'Call ended';

    if (duration) {
      const minutes = Math.floor(duration / 60);
      const seconds = duration % 60;
      message = `Call ended - Duration: ${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    if (reason) {
      message += ` (${reason})`;
    }

    window.bus.$emit('newToastMessage', {
      message,
      type: 'info',
    });
  };
}

export default WhatsAppCallsActionCableConnector;
