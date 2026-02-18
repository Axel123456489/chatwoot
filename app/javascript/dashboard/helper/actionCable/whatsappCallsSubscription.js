// ActionCable integration for WhatsApp calls
// Replaces polling with real-time WebSocket updates

import { emitter } from 'shared/helpers/mitt';

class WhatsAppCallsSubscription {
  constructor(consumer) {
    this.consumer = consumer;
    this.subscription = null;
  }

  // Subscribe to a specific call
  subscribeToCall(callId, callbacks = {}) {
    if (this.subscription) {
      this.unsubscribe();
    }

    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'WhatsappCallsChannel',
        call_id: callId,
      },
      {
        connected: () => {
          callbacks.onConnected?.();
        },

        disconnected: () => {
          callbacks.onDisconnected?.();
        },

        received: data => {
          this.handleMessage(data, callbacks);
        },
      }
    );

    return this.subscription;
  }

  // Subscribe to all calls in a conversation
  subscribeToConversation(conversationId, callbacks = {}) {
    if (this.subscription) {
      this.unsubscribe();
    }

    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'WhatsappCallsChannel',
        conversation_id: conversationId,
      },
      {
        connected: () => {
          callbacks.onConnected?.();
        },

        disconnected: () => {
          callbacks.onDisconnected?.();
        },

        received: data => {
          this.handleMessage(data, callbacks);
        },
      }
    );

    return this.subscription;
  }

  // Subscribe to all account calls
  subscribeToAccount(callbacks = {}) {
    if (this.subscription) {
      this.unsubscribe();
    }

    this.subscription = this.consumer.subscriptions.create(
      {
        channel: 'WhatsappCallsChannel',
      },
      {
        connected: () => {
          callbacks.onConnected?.();
        },

        disconnected: () => {
          callbacks.onDisconnected?.();
        },

        received: data => {
          this.handleMessage(data, callbacks);
        },
      }
    );

    return this.subscription;
  }

  // eslint-disable-next-line class-methods-use-this
  handleMessage(data, callbacks) {
    const { type, event } = data;

    // Handle different message types
    if (type === 'status_update' || event === 'whatsapp_call_status_changed') {
      callbacks.onStatusUpdate?.(data);

      // Emit global event for other components
      emitter.emit('whatsapp_call_status_changed', data);
    }

    // Handle SDP answer
    if (data.sdpAnswer) {
      callbacks.onSdpAnswer?.(data.sdpAnswer, data.iceCandidates);
      emitter.emit('whatsapp_call_sdp_answer', data);
    }

    // Handle errors
    if (data.error) {
      callbacks.onError?.(data.error);
      emitter.emit('whatsapp_call_error', data);
    }

    // Call generic callback if provided
    callbacks.onMessage?.(data);
  }

  // Request current status
  requestStatus(callId) {
    if (!this.subscription) {
      return;
    }

    this.subscription.perform('request_status', { call_id: callId });
  }

  // Report quality metrics
  reportQuality(callId, metricName, value) {
    if (!this.subscription) {
      return;
    }

    this.subscription.perform('report_quality', {
      call_id: callId,
      metric_name: metricName,
      value: value,
    });
  }

  unsubscribe() {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
  }
}

export default WhatsAppCallsSubscription;
