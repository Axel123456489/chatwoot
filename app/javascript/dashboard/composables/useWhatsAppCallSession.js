import { ref, computed, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import WhatsappCallsAPI from '../api/whatsapp/calls';

/**
 * Composable for managing WhatsApp call sessions
 * Provides reactive state and methods for call operations
 */
export const useWhatsAppCallSession = () => {
  const store = useStore();
  const { showAlert } = useAlert();

  // Reactive state
  const isInitiating = ref(false);
  const isTerminating = ref(false);
  const currentCallId = ref(null);
  const callError = ref(null);

  // Computed properties from store
  const activeCall = computed(
    () => store.getters['whatsappCalls/getActiveCall']
  );
  const incomingCalls = computed(
    () => store.getters['whatsappCalls/getIncomingCalls']
  );
  const hasActiveCall = computed(
    () => store.getters['whatsappCalls/hasActiveCall']
  );
  const hasIncomingCalls = computed(
    () => store.getters['whatsappCalls/hasIncomingCalls']
  );

  const callStatus = computed(() => activeCall.value?.status || 'idle');

  const isConnected = computed(() => {
    return ['connected', 'on_hold'].includes(callStatus.value);
  });

  const isRinging = computed(() => {
    return callStatus.value === 'ringing';
  });

  /**
   * Initiate an outbound call
   * @param {Object} params - Call parameters
   * @param {Number} params.conversationId - Conversation ID
   * @param {Number} params.inboxId - Inbox ID
   * @param {Number} params.accountId - Account ID
   * @returns {Promise<Object>} Call result
   */
  const initiateCall = async ({ conversationId, inboxId, accountId }) => {
    if (hasActiveCall.value) {
      throw new Error('There is already an active call');
    }

    isInitiating.value = true;
    callError.value = null;

    try {
      const result = await store.dispatch('whatsappCalls/initiateCall', {
        conversationId,
        inboxId,
        accountId,
      });

      currentCallId.value = result.data.call_id;
      showAlert('Call initiated successfully');

      return result;
    } catch (error) {
      callError.value = error.message;

      // Handle specific errors
      if (error.response?.status === 403) {
        showAlert("You don't have permission to call this contact");
      } else if (error.response?.status === 429) {
        showAlert('Daily call limit reached for this contact');
      } else {
        showAlert(error.message || 'Failed to initiate call');
      }

      throw error;
    } finally {
      isInitiating.value = false;
    }
  };

  /**
   * Terminate an active call
   * @param {Object} params - Termination parameters
   * @param {String} params.callId - Call ID to terminate
   * @param {Number} params.conversationId - Conversation ID
   * @param {Number} params.accountId - Account ID
   * @returns {Promise<void>}
   */
  const terminateCall = async ({ callId, conversationId, accountId }) => {
    if (!callId && !activeCall.value) {
      throw new Error('No active call to terminate');
    }

    const targetCallId = callId || activeCall.value.id;
    isTerminating.value = true;

    try {
      await store.dispatch('whatsappCalls/terminateCall', {
        accountId,
        callId: targetCallId,
        conversationId,
      });

      currentCallId.value = null;
      showAlert('Call ended');
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to end call');
      throw error;
    } finally {
      isTerminating.value = false;
    }
  };

  /**
   * Accept an incoming call
   * @param {String} callId - Call ID to accept
   * @returns {Promise<void>}
   */
  const acceptIncomingCall = async callId => {
    try {
      await store.dispatch('whatsappCalls/acceptIncomingCall', callId);
      currentCallId.value = callId;
      showAlert('Call accepted');
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to accept call');
      throw error;
    }
  };

  /**
   * Reject an incoming call
   * @param {String} callId - Call ID to reject
   * @returns {Promise<void>}
   */
  const rejectIncomingCall = async callId => {
    try {
      await store.dispatch('whatsappCalls/rejectIncomingCall', callId);
      showAlert('Call rejected');
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to reject call');
      throw error;
    }
  };

  /**
   * Toggle mute state of active call
   * @returns {Promise<void>}
   */
  const toggleMute = async () => {
    if (!activeCall.value) return;

    try {
      const newMuteState = !activeCall.value.is_muted;

      // Update local state immediately for better UX
      store.commit('whatsappCalls/updateActiveCall', {
        is_muted: newMuteState,
      });

      // TODO: Send mute state to media server
      showAlert(newMuteState ? 'Microphone muted' : 'Microphone unmuted');
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to toggle mute');
      throw error;
    }
  };

  /**
   * Toggle hold state of active call
   * @returns {Promise<void>}
   */
  const toggleHold = async () => {
    if (!activeCall.value) return;

    try {
      const newHoldState =
        activeCall.value.status === 'on_hold' ? 'connected' : 'on_hold';

      // Update local state
      store.commit('whatsappCalls/updateActiveCall', {
        status: newHoldState,
      });

      // TODO: Send hold state to media server
      showAlert(newHoldState === 'on_hold' ? 'Call on hold' : 'Call resumed');
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to toggle hold');
      throw error;
    }
  };

  /**
   * Get call history for a conversation
   * @param {Object} params - History parameters
   * @param {Number} params.accountId - Account ID
   * @param {Number} params.conversationId - Conversation ID
   * @param {Number} params.page - Page number
   * @returns {Promise<Object>} Call history data
   */
  const fetchCallHistory = async ({ accountId, conversationId, page = 1 }) => {
    try {
      const result = await store.dispatch('whatsappCalls/fetchHistory', {
        accountId,
        conversationId,
        page,
      });

      return result;
    } catch (error) {
      callError.value = error.message;
      showAlert('Failed to load call history');
      throw error;
    }
  };

  /**
   * Request call permission from a contact
   * @param {Object} params - Permission request parameters
   * @param {Number} params.accountId - Account ID
   * @param {Number} params.contactId - Contact ID
   * @param {Number} params.inboxId - Inbox ID
   * @returns {Promise<Object>} Permission result
   */
  const requestCallPermission = async ({ accountId, contactId, inboxId }) => {
    try {
      const response = await WhatsappCallsAPI.requestPermission({
        accountId,
        contactId,
        inboxId,
      });

      showAlert('Permission request sent');
      return response;
    } catch (error) {
      if (error.response?.status === 409) {
        showAlert('Permission already requested or granted');
      } else {
        showAlert('Failed to request permission');
      }
      throw error;
    }
  };

  /**
   * Check call permission status for a contact
   * @param {Object} params - Permission check parameters
   * @param {Number} params.accountId - Account ID
   * @param {Number} params.contactId - Contact ID
   * @param {Number} params.inboxId - Inbox ID
   * @returns {Promise<Object>} Permission status
   */
  const checkCallPermission = async ({ accountId, contactId, inboxId }) => {
    try {
      const response = await WhatsappCallsAPI.getPermission({
        accountId,
        contactId,
        inboxId,
      });

      return response.data.permission;
    } catch (error) {
      callError.value = error.message;
      throw error;
    }
  };

  /**
   * Clear call error
   */
  const clearError = () => {
    callError.value = null;
  };

  /**
   * Clear active call from store
   */
  const clearActiveCall = () => {
    store.dispatch('whatsappCalls/clearActiveCall');
    currentCallId.value = null;
  };

  // Cleanup on unmount
  onUnmounted(() => {
    clearError();
  });

  return {
    // State
    isInitiating,
    isTerminating,
    currentCallId,
    callError,
    activeCall,
    incomingCalls,
    hasActiveCall,
    hasIncomingCalls,
    callStatus,
    isConnected,
    isRinging,

    // Methods
    initiateCall,
    terminateCall,
    acceptIncomingCall,
    rejectIncomingCall,
    toggleMute,
    toggleHold,
    fetchCallHistory,
    requestCallPermission,
    checkCallPermission,
    clearError,
    clearActiveCall,
  };
};

export default useWhatsAppCallSession;
