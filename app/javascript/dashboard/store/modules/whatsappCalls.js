import WhatsappCallsAPI from '../../api/whatsapp/calls';
import { throwErrorMessage } from '../utils/api';

export const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isInitiating: false,
    isTerminating: false,
  },
  activeCall: null,
  incomingCalls: [],
  callHistory: [],
};

export const getters = {
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getActiveCall($state) {
    return $state.activeCall;
  },
  getIncomingCalls($state) {
    return $state.incomingCalls;
  },
  getCallHistory($state) {
    return $state.callHistory;
  },
  getCallById: $state => callId => {
    return $state.records[callId];
  },
  hasActiveCall($state) {
    return $state.activeCall !== null;
  },
  hasIncomingCalls($state) {
    return $state.incomingCalls.length > 0;
  },
};

export const actions = {
  async initiateCall({ commit }, { accountId, conversationId, inboxId }) {
    commit('setInitiating', true);

    try {
      const response = await WhatsappCallsAPI.initiateCall({
        accountId,
        conversationId,
        inboxId,
      });

      commit('setActiveCall', response.data);
      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('setInitiating', false);
    }
  },

  async setupWebRTC(_, payload) {
    try {
      const response = await WhatsappCallsAPI.setupWebRTC(payload);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  async terminateCall({ commit }, { accountId, callId, conversationId, duration }) {
    commit('setTerminating', true);

    try {
      const response = await WhatsappCallsAPI.terminateCall({
        accountId,
        callId,
        conversationId,
        duration,
      });

      commit('clearActiveCall');
      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('setTerminating', false);
    }
  },

  async fetchHistory({ commit }, { accountId, conversationId, page = 1 }) {
    commit('setFetching', true);

    try {
      const response = await WhatsappCallsAPI.getCallHistory({
        accountId,
        conversationId,
        page,
      });

      if (page === 1) {
        commit('setCallHistory', response.data.calls);
      } else {
        commit('appendCallHistory', response.data.calls);
      }

      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit('setFetching', false);
    }
  },

  handleIncomingCall({ commit, state: $state }, callData) {
    // Add to incoming calls if not already present
    const existingCall = $state.incomingCalls.find(
      call => call.id === callData.id
    );

    if (!existingCall) {
      commit('addIncomingCall', callData);
    }
  },

  async acceptCall({ commit, state: $state }, { accountId, callId }) {
    try {
      const response = await WhatsappCallsAPI.acceptCall({
        accountId,
        callId,
      });

      // Find the call in incoming calls
      const call = $state.incomingCalls.find(c => c.id === callId);

      if (call) {
        // Set as active call
        commit('setActiveCall', { ...call, status: 'connected' });
      }

      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  async answerCall(
    { commit, state: $state },
    { accountId, callId, conversationId, sdpAnswer }
  ) {
    try {
      const response = await WhatsappCallsAPI.answerCall({
        accountId,
        callId,
        conversationId,
        sdpAnswer,
      });

      // Find the call in incoming calls
      const call = $state.incomingCalls.find(c => c.id === callId);

      if (call) {
        // Set as active call
        commit('setActiveCall', { ...call, status: 'connected' });
      }

      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  async rejectCall(_, { accountId, callId, reason = 'declined' }) {
    try {
      const response = await WhatsappCallsAPI.rejectCall({
        accountId,
        callId,
        reason,
      });

      return response;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    }
  },

  removeIncomingCall({ commit }, callId) {
    commit('removeIncomingCall', callId);
  },

  acceptIncomingCall({ commit, state: $state }, callId) {
    const call = $state.incomingCalls.find(c => c.id === callId);

    if (call) {
      commit('setActiveCall', call);
      commit('removeIncomingCall', callId);
    }
  },

  rejectIncomingCall({ commit }, callId) {
    commit('removeIncomingCall', callId);
  },

  updateCallState({ commit, state: $state }, { callId, stateData }) {
    if ($state.activeCall && $state.activeCall.id === callId) {
      commit('updateActiveCall', stateData);
    }

    // Update in records
    commit('updateCallRecord', { callId, stateData });
  },

  clearActiveCall({ commit }) {
    commit('clearActiveCall');
  },
};

export const mutations = {
  setFetching($state, status) {
    $state.uiFlags.isFetching = status;
  },

  setInitiating($state, status) {
    $state.uiFlags.isInitiating = status;
  },

  setTerminating($state, status) {
    $state.uiFlags.isTerminating = status;
  },

  setActiveCall($state, call) {
    $state.activeCall = call;
    $state.records[call.id] = call;
  },

  updateActiveCall($state, stateData) {
    if ($state.activeCall) {
      $state.activeCall = { ...$state.activeCall, ...stateData };
      $state.records[$state.activeCall.id] = $state.activeCall;
    }
  },

  clearActiveCall($state) {
    if ($state.activeCall) {
      // Move to history
      const existingHistoryIndex = $state.callHistory.findIndex(
        call => call.id === $state.activeCall.id
      );

      if (existingHistoryIndex >= 0) {
        $state.callHistory.splice(existingHistoryIndex, 1, $state.activeCall);
      } else {
        $state.callHistory.unshift($state.activeCall);
      }
    }

    $state.activeCall = null;
  },

  addIncomingCall($state, call) {
    $state.incomingCalls.push(call);
    $state.records[call.id] = call;
  },

  removeIncomingCall($state, callId) {
    $state.incomingCalls = $state.incomingCalls.filter(
      call => call.id !== callId
    );
  },

  setCallHistory($state, calls) {
    $state.callHistory = calls;
    calls.forEach(call => {
      $state.records[call.id] = call;
    });
  },

  appendCallHistory($state, calls) {
    $state.callHistory = [...$state.callHistory, ...calls];
    calls.forEach(call => {
      $state.records[call.id] = call;
    });
  },

  updateCallRecord($state, { callId, stateData }) {
    if ($state.records[callId]) {
      $state.records[callId] = { ...$state.records[callId], ...stateData };
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
