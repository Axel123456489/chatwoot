/* global axios */
import ApiClient from '../ApiClient';

class WhatsappCallsAPI extends ApiClient {
  constructor() {
    super('whatsapp/calls', { accountScoped: true });
  }

  // Initiate an outbound call
  initiateCall({ conversationId, inboxId }) {
    return axios.post(`${this.url}`, {
      conversation_id: conversationId,
      inbox_id: inboxId,
    });
  }

  // Terminate an active call
  terminateCall({ callId, conversationId, duration }) {
    return axios.post(`${this.url}/terminate`, {
      call_id: callId,
      conversation_id: conversationId,
      duration,
    });
  }

  // Accept an incoming call
  acceptCall({ callId }) {
    return axios.post(`${this.url}/${callId}/accept`);
  }

  // Answer an incoming call with SDP answer (WebRTC)
  answerCall({ callId, conversationId, sdpAnswer }) {
    return axios.post(`${this.url}/answer`, {
      call_id: callId,
      conversation_id: conversationId,
      sdp_answer: sdpAnswer,
    });
  }

  // Reject an incoming call
  rejectCall({ callId, reason = 'declined' }) {
    return axios.post(`${this.url}/${callId}/reject`, {
      reason,
    });
  }

  // Send ICE candidate(s) to backend
  trickleIce({ conversationId, callId, candidate, candidates }) {
    const url = `${this.url}/trickle`;
    return axios.post(url, {
      conversation_id: conversationId,
      call_id: callId,
      candidate,
      candidates,
    });
  }

  // Exchange WebRTC SDP offer for WhatsApp-generated answer
  setupWebRTC({ conversationId, callId, sdpOffer }) {
    const url = `${this.url}/setup_webrtc`;

    return axios.post(url, {
      conversation_id: conversationId,
      call_id: callId,
      sdp_offer: sdpOffer,
    });
  }

  // Request call permission from a contact
  requestPermission({ contactId, inboxId }) {
    return axios.post(`${this.url}/request_permission`, {
      contact_id: contactId,
      inbox_id: inboxId,
    });
  }

  // Get call permission for a contact
  getPermission({ contactId, inboxId }) {
    return axios.get(`${this.url}/permissions`, {
      params: {
        contact_id: contactId,
        inbox_id: inboxId,
      },
    });
  }

  // Get call history for a conversation
  getCallHistory({ conversationId }) {
    return axios.get(`${this.url}/history`, {
      params: {
        conversation_id: conversationId,
      },
    });
  }

  // Get call analytics
  getAnalytics({ startDate, endDate, inboxId }) {
    return axios.get(`${this.url}/analytics`, {
      params: {
        start_date: startDate,
        end_date: endDate,
        inbox_id: inboxId,
      },
    });
  }

  // Upload call recording from browser
  uploadRecording({ conversationId, formData }) {
    // Use conversation_id in URL to avoid URL encoding issues with long call_ids
    const url = `${this.baseUrl()}/conversations/${conversationId}/whatsapp_call_recording`;
    return axios.post(url, formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });
  }
}

export default new WhatsappCallsAPI();
