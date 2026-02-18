import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { useImpersonation } from 'dashboard/composables/useImpersonation';

const { isImpersonating } = useImpersonation();

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = [];
    this.events = {
      'message.created': this.onMessageCreated,
      'message.updated': this.onMessageUpdated,
      'conversation.created': this.onConversationCreated,
      'conversation.status_changed': this.onStatusChange,
      'user:logout': this.onLogout,
      'page:reload': this.onReload,
      'assignee.changed': this.onAssigneeChanged,
      'conversation.typing_on': this.onTypingOn,
      'conversation.typing_off': this.onTypingOff,
      'conversation.contact_changed': this.onConversationContactChange,
      'presence.update': this.onPresenceUpdate,
      'contact.deleted': this.onContactDelete,
      'contact.updated': this.onContactUpdate,
      'conversation.mentioned': this.onConversationMentioned,
      'notification.created': this.onNotificationCreated,
      'notification.deleted': this.onNotificationDeleted,
      'notification.updated': this.onNotificationUpdated,
      'conversation.read': this.onConversationRead,
      'conversation.updated': this.onConversationUpdated,
      'account.cache_invalidated': this.onCacheInvalidate,
      'copilot.message.created': this.onCopilotMessageCreated,
      whatsapp_incoming_call: this.onWhatsappIncomingCall,
      whatsapp_call_created: this.onWhatsappCallCreated,
      whatsapp_call_status_changed: this.onWhatsappCallStatusChanged,
      whatsapp_call_terminated: this.onWhatsAppCallTerminated,
      whatsapp_call_sdp_answer: this.onWhatsappCallSdpAnswer,
    };
  }

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
  };

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT);
  };

  isAValidEvent = data => {
    // If data is undefined or doesn't have account_id, reject it
    if (!data || !data.account_id) {
      return false;
    }
    const currentAccountId = this.app.$store.getters.getCurrentAccountId;
    return currentAccountId === data.account_id;
  };

  onMessageUpdated = data => {
    this.app.$store.dispatch('updateMessage', data);
  };

  onPresenceUpdate = data => {
    if (isImpersonating.value) return;
    this.app.$store.dispatch('contacts/updatePresence', data.contacts);
    this.app.$store.dispatch('agents/updatePresence', data.users);
    this.app.$store.dispatch('setCurrentUserAvailability', data.users);
  };

  onConversationContactChange = payload => {
    const { meta = {}, id: conversationId } = payload;
    const { sender } = meta || {};
    if (conversationId) {
      this.app.$store.dispatch('updateConversationContact', {
        conversationId,
        ...sender,
      });
    }
  };

  onAssigneeChanged = payload => {
    const { id } = payload;
    if (id) {
      this.app.$store.dispatch('updateConversation', payload);
    }
    this.fetchConversationStats();
  };

  onConversationCreated = data => {
    this.app.$store.dispatch('addConversation', data);
    this.fetchConversationStats();
  };

  onConversationRead = data => {
    this.app.$store.dispatch('updateConversation', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onLogout = () => AuthAPI.logout();

  onMessageCreated = data => {
    const {
      conversation: { last_activity_at: lastActivityAt },
      conversation_id: conversationId,
    } = data;
    DashboardAudioNotificationHelper.onNewMessage(data);
    this.app.$store.dispatch('addMessage', data);
    this.app.$store.dispatch('updateConversationLastActivity', {
      lastActivityAt,
      conversationId,
    });
  };

  // eslint-disable-next-line class-methods-use-this
  onReload = () => window.location.reload();

  onStatusChange = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onConversationUpdated = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onTypingOn = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId,
      user,
    });
    this.initTimer({ conversation, user });
  };

  onTypingOff = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
  };

  clearTimer = conversationId => {
    const timerEvent = this.CancelTyping[conversationId];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[conversationId] = null;
    }
  };

  initTimer = ({ conversation, user }) => {
    const conversationId = conversation.id;
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[conversationId] = setTimeout(() => {
      this.onTypingOff({ conversation, user });
    }, 30000);
  };

  // eslint-disable-next-line class-methods-use-this
  fetchConversationStats = () => {
    emitter.emit('fetch_conversation_stats');
  };

  onContactDelete = data => {
    this.app.$store.dispatch(
      'contacts/deleteContactThroughConversations',
      data.id
    );
    this.fetchConversationStats();
  };

  onContactUpdate = data => {
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onNotificationCreated = data => {
    this.app.$store.dispatch('notifications/addNotification', data);
  };

  onNotificationDeleted = data => {
    this.app.$store.dispatch('notifications/deleteNotification', data);
  };

  onNotificationUpdated = data => {
    this.app.$store.dispatch('notifications/updateNotification', data);
  };

  onCopilotMessageCreated = data => {
    this.app.$store.dispatch('copilotMessages/upsert', data);
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });
  };

  onWhatsAppCallTerminated = data => {
    // Emit event to bus for components to listen
    emitter.emit('whatsapp_call_terminated', data);
    // Also dispatch to store if needed
    if (data.conversation_id) {
      this.app.$store.dispatch('whatsappCalls/clearActiveCall');
    }
  };

  onWhatsappIncomingCall = data => {
    const call = this.normalizeWhatsappCallPayload(data?.call);
    if (!call) return;

    this.dispatchWhatsappIncomingCall(call);
  };

  // Some inbound flows publish `whatsapp_call_created` with a flat payload.
  // Normalize it to the shape used by the WhatsApp call UI.
  onWhatsappCallCreated = data => {
    // `whatsapp_call_created` can be emitted for both inbound and outbound calls.
    // Only inbound calls should be shown as an incoming call that needs answering.
    const direction = data?.direction;
    if (direction && direction !== 'inbound') return;

    const call = this.normalizeWhatsappCallPayload(data);
    if (!call) return;

    this.dispatchWhatsappIncomingCall(call);
  };

  // eslint-disable-next-line class-methods-use-this
  normalizeWhatsappCallPayload = call => {
    const callId = call?.call_id || call?.id;
    if (!callId) return null;

    return {
      id: callId,
      call_id: callId,
      conversation_id: call?.conversation_id,
      conversation_display_id:
        call?.conversation_display_id || call?.conversation_id,
      status: call?.status || 'ringing',
      direction: call?.direction || 'inbound',
      contact_name: call?.contact_name,
      from_number: call?.from_number,
      to_number: call?.to_number,
      sdp_offer: call?.sdp_offer,
    };
  };

  dispatchWhatsappIncomingCall = call => {
    // Keep the existing WhatsApp calling flow working.
    // The WhatsApp call UI uses the Vuex `whatsappCalls` module for inbound calls.
    try {
      this.app.$store.dispatch('whatsappCalls/handleIncomingCall', call);
    } catch (error) {
      // no-op
    }

    // Add to calls store (used by FloatingCallWidget)
    const callData = {
      callSid: call.call_id,
      conversationId: call.conversation_id,
      callDirection: 'inbound',
      channelType: 'whatsapp',
      contactName: call.contact_name,
      fromNumber: call.from_number,
      status: call.status,
      sdpOffer: call.sdp_offer,
    };

    // Import and use Pinia store
    import('dashboard/stores/calls')
      .then(({ useCallsStore }) => {
        const callsStore = useCallsStore();
        callsStore.addCall(callData);
      })
      .catch(() => {
        // no-op
      });

    emitter.emit('whatsapp_incoming_call', call);
  };

  // eslint-disable-next-line class-methods-use-this
  onWhatsappCallSdpAnswer = data => {
    // Emit event to bus for useWhatsAppCall to handle
    emitter.emit('whatsapp_call_sdp_answer', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onWhatsappCallStatusChanged = data => {
    // Emit event to bus for useWhatsAppCall to handle
    emitter.emit('whatsapp_call_status_changed', data);
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
