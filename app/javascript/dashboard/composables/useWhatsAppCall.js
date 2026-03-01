/* eslint-disable no-use-before-define */
import { ref, computed, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import WhatsappCallsAPI from 'dashboard/api/whatsapp/calls';
import MessageApi from 'dashboard/api/inbox/message';
import mutationTypes from 'dashboard/store/mutation-types';

export function useWhatsAppCall() {
  const store = useStore();

  const currentCallId = ref(null);
  const peerConnection = ref(null);
  const localStream = ref(null);
  const remoteStream = ref(null);
  const callStatus = ref('idle'); // idle, connecting, ringing, connected, ended
  const isMuted = ref(false);
  const callDuration = ref(0);
  const timerStarted = ref(false); // Track if timer has been started for current call
  const calleeAccepted = ref(false); // Outbound: WhatsApp status ACCEPTED received
  const isTerminating = ref(false); // Flag to prevent multiple terminate calls

  // Store conversation display_id at call start for later use
  const savedConversationId = ref(null);
  const savedAccountId = ref(null);

  // Recording state
  const mediaRecorder = ref(null);
  const recordedChunks = ref([]);
  const isRecording = ref(false);
  const recordingAudioContext = ref(null);
  const recordingDestination = ref(null);
  const remoteSourceNode = ref(null);
  let uploadCompleteResolver = null; // To signal when upload is done

  let callTimer = null;
  const iceCandidatesQueue = []; // Buffer candidates until SDP answer received
  let sdpAnswerReceived = false; // Track if we can send ICE candidates

  const maybeStartOutboundTimerAndRecording = () => {
    if (timerStarted.value) return;
    if (!calleeAccepted.value) return;
    if (!sdpAnswerReceived) return;
    if (
      !peerConnection.value ||
      peerConnection.value.connectionState !== 'connected'
    )
      return;

    callStatus.value = 'connected';
    startCallTimer();
    timerStarted.value = true;

    setTimeout(() => {
      if (!isRecording.value && callStatus.value === 'connected') {
        startRecording();
      }
    }, 500);
  };

  // WebRTC configuration
  const rtcConfig = {
    iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
    ],
  };

  const sleep = duration =>
    new Promise(resolve => {
      setTimeout(resolve, duration);
    });

  /**
   * Start recording both local (agent) and remote (client) audio
   */
  function isRecordingAllowed() {
    const chat = store.getters.getSelectedChat;
    if (!chat?.inbox_id) return false;
    const inbox = store.getters['inboxes/getInbox'](chat.inbox_id);
    return inbox?.calling_config?.recording_enabled === true;
  }

  function startRecording() {
    if (!isRecordingAllowed()) {
      return;
    }
    try {
      if (!localStream.value) {
        return;
      }

      // Create AudioContext to mix local and remote streams
      recordingAudioContext.value = new AudioContext();
      recordingDestination.value =
        recordingAudioContext.value.createMediaStreamDestination();

      // Mix local stream (agent microphone)
      const localSource = recordingAudioContext.value.createMediaStreamSource(
        localStream.value
      );
      localSource.connect(recordingDestination.value);

      // Mix remote stream (WhatsApp client) if available
      if (remoteStream.value) {
        remoteSourceNode.value =
          recordingAudioContext.value.createMediaStreamSource(
            remoteStream.value
          );
        remoteSourceNode.value.connect(recordingDestination.value);
      }

      // Create MediaRecorder with mixed stream
      const options = { mimeType: 'audio/webm;codecs=opus' };
      if (!MediaRecorder.isTypeSupported(options.mimeType)) {
        mediaRecorder.value = new MediaRecorder(
          recordingDestination.value.stream
        );
      } else {
        mediaRecorder.value = new MediaRecorder(
          recordingDestination.value.stream,
          options
        );
      }

      recordedChunks.value = [];

      mediaRecorder.value.ondataavailable = event => {
        if (event.data.size > 0) {
          recordedChunks.value.push(event.data);
        }
      };

      mediaRecorder.value.onstop = async () => {
        // Upload recording and WAIT for it to complete
        await uploadRecording();

        // Now it's safe to reset recording state
        mediaRecorder.value = null;
        recordedChunks.value = [];
        isRecording.value = false;

        // Clean up audio context if not already closed
        if (
          recordingAudioContext.value &&
          recordingAudioContext.value.state !== 'closed'
        ) {
          recordingAudioContext.value.close();
          recordingAudioContext.value = null;
          recordingDestination.value = null;
          remoteSourceNode.value = null;
        }

        // Signal that upload is complete
        if (uploadCompleteResolver) {
          uploadCompleteResolver();
          uploadCompleteResolver = null;
        }
      };

      mediaRecorder.value.start(1000); // Capture in 1-second chunks
      isRecording.value = true;
    } catch (error) {
      String(error);
    }
  }

  /**
   * Add remote stream to recording if it arrives after recording has started
   */
  const addRemoteStreamToRecording = () => {
    if (
      isRecording.value &&
      recordingAudioContext.value &&
      recordingDestination.value &&
      remoteStream.value &&
      !remoteSourceNode.value
    ) {
      try {
        remoteSourceNode.value =
          recordingAudioContext.value.createMediaStreamSource(
            remoteStream.value
          );
        remoteSourceNode.value.connect(recordingDestination.value);
      } catch (error) {
        String(error);
      }
    }
  };

  /**
   * Stop recording and wait for upload to complete
   */
  const stopRecording = () => {
    return new Promise(resolve => {
      if (!mediaRecorder.value || !isRecording.value) {
        resolve();
        return;
      }

      // Store the resolver to be called when upload completes
      uploadCompleteResolver = resolve;

      // Stop the recorder - this will trigger onstop which handles upload
      mediaRecorder.value.stop();
      isRecording.value = false;

      // Safety timeout - resolve after 30 seconds max
      setTimeout(() => {
        if (uploadCompleteResolver) {
          uploadCompleteResolver();
          uploadCompleteResolver = null;
        }
      }, 30000);
    });
  };

  /**
   * Upload recording to server
   */
  async function uploadRecording() {
    if (recordedChunks.value.length === 0) {
      return;
    }

    try {
      const blob = new Blob(recordedChunks.value, { type: 'audio/webm' });

      if (blob.size === 0) {
        return;
      }

      const accountId = savedAccountId.value;
      const conversationId = savedConversationId.value;

      if (!accountId || !conversationId || !currentCallId.value) {
        return;
      }

      const formData = new FormData();
      formData.append(
        'recording',
        blob,
        `call_${currentCallId.value}_${Date.now()}.webm`
      );
      formData.append('call_id', currentCallId.value); // Include call_id in body
      formData.append('duration', callDuration.value); // Include call duration in seconds

      const uploadResponse = await WhatsappCallsAPI.uploadRecording({
        accountId,
        conversationId,
        callId: currentCallId.value,
        formData,
      });

      // Backend responds with message_id + attachment_count but message.updated
      // websocket payload may not include attachments. Fetch the updated message
      // so UI can render the recording immediately.
      const uploadedMessageId = uploadResponse?.data?.message_id;
      const attachmentCount = uploadResponse?.data?.attachment_count;
      if (uploadedMessageId && attachmentCount > 0) {
        try {
          const {
            data: { payload },
          } = await MessageApi.getPreviousMessages({
            conversationId,
            after: uploadedMessageId,
            before: uploadedMessageId + 1,
          });

          const updatedMessage = (payload || []).find(
            m => m.id === uploadedMessageId
          );
          if (updatedMessage) {
            store.dispatch('updateMessage', updatedMessage);
            store.commit(
              mutationTypes.ADD_CONVERSATION_ATTACHMENTS,
              updatedMessage
            );
          }
        } catch (error) {
          String(error);
        }
      }

      // Show success notification
      emitter.emit('newToastMessage', {
        message: 'Grabación de llamada guardada',
        type: 'success',
      });
    } catch (error) {
      String(error);
      emitter.emit('newToastMessage', {
        message: 'Error al guardar la grabación',
        type: 'error',
      });
    }
  }

  /**
   * Pre-request microphone permissions to reduce latency on call initiation
   * This can be called when user opens conversation or hovers over call button
   */
  const prepareMediaStream = async () => {
    // Don't request if already have stream or call is active
    if (localStream.value || callStatus.value !== 'idle') {
      return;
    }

    try {
      localStream.value = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: false,
      });
    } catch (error) {
      String(error);
      // Don't throw - user can still grant permission when actually calling
    }
  };

  /**
   * Initialize WebRTC connection for outbound call (P2P mode with WhatsApp)
   */
  const initiateCall = async ({ accountId, conversationId, callId }) => {
    try {
      callStatus.value = 'connecting';
      currentCallId.value = callId;
      calleeAccepted.value = false;

      // Save IDs for later use (e.g., recording upload)
      savedAccountId.value = accountId;
      savedConversationId.value = conversationId;

      // Get user media (microphone) - reuse if already prepared
      if (!localStream.value) {
        localStream.value = await navigator.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
          video: false,
        });
      }

      // Create peer connection
      peerConnection.value = new RTCPeerConnection(rtcConfig);

      // ICE connection state handler - detect disconnections
      peerConnection.value.oniceconnectionstatechange = () => {
        const state = peerConnection.value.iceConnectionState;
        if (
          state === 'disconnected' ||
          state === 'failed' ||
          state === 'closed'
        ) {
          if (!isTerminating.value) {
            endCall();
          }
        }
      };

      // Add local stream to connection
      localStream.value.getTracks().forEach(track => {
        peerConnection.value.addTrack(track, localStream.value);
      });

      // Handle remote stream
      peerConnection.value.ontrack = event => {
        if (event.streams && event.streams[0]) {
          remoteStream.value = event.streams[0];
          playRemoteAudio();

          // If recording has already started, add remote stream to it
          addRemoteStreamToRecording();
        }
      };

      // Handle connection state changes
      peerConnection.value.onconnectionstatechange = () => {
        const state = peerConnection.value.connectionState;
        if (state === 'connected') {
          // Outbound calls:
          // - SDP answer can arrive before ACCEPTED (WhatsApp ordering)
          // - only start timer/recording after ACCEPTED + WebRTC connected
          if (calleeAccepted.value && sdpAnswerReceived) {
            maybeStartOutboundTimerAndRecording();
          } else {
            callStatus.value = 'ringing';
          }
        } else if (
          state === 'disconnected' ||
          state === 'failed' ||
          state === 'closed'
        ) {
          if (!isTerminating.value) {
            endCall();
          }
        }
      };

      // Create SDP offer
      const offer = await peerConnection.value.createOffer();
      await peerConnection.value.setLocalDescription(offer);

      // Wait for ICE gathering to complete (WhatsApp needs all candidates in offer)
      await new Promise(resolve => {
        if (peerConnection.value.iceGatheringState === 'complete') {
          resolve();
        } else {
          const checkState = () => {
            if (peerConnection.value.iceGatheringState === 'complete') {
              peerConnection.value.removeEventListener(
                'icegatheringstatechange',
                checkState
              );
              resolve();
            }
          };
          peerConnection.value.addEventListener(
            'icegatheringstatechange',
            checkState
          );

          // Safety timeout
          setTimeout(() => {
            peerConnection.value.removeEventListener(
              'icegatheringstatechange',
              checkState
            );
            resolve();
          }, 3000);
        }
      });

      // Get final SDP with all ICE candidates
      const finalOffer = peerConnection.value.localDescription;

      // Send offer to backend and wait for WhatsApp answer
      const response = await store.dispatch('whatsappCalls/setupWebRTC', {
        accountId,
        conversationId,
        callId: currentCallId.value,
        sdpOffer: finalOffer.sdp,
      });

      if (response && response.callId) {
        currentCallId.value = response.callId;
      }

      // Apply WhatsApp SDP answer
      if (response && response.sdpAnswer) {
        await peerConnection.value.setRemoteDescription({
          type: 'answer',
          sdp: response.sdpAnswer,
        });

        sdpAnswerReceived = true;
        callStatus.value = 'ringing';
      }
      return { success: true };
    } catch (error) {
      callStatus.value = 'idle';
      cleanup();
      return { success: false, error: error.message };
    }
  };

  /**
   * Answer incoming call
   */
  const answerCall = async ({
    accountId,
    sdpOffer,
    conversationId,
    callId,
  }) => {
    try {
      if (!sdpOffer || sdpOffer.trim().length === 0) {
        throw new Error('SDP offer is missing or empty');
      }

      if (!sdpOffer.startsWith('v=')) {
        throw new Error('Invalid SDP format: must start with "v="');
      }

      callStatus.value = 'connecting';
      currentCallId.value = callId;

      // Save IDs for later use (e.g., recording upload)
      savedAccountId.value = accountId;
      savedConversationId.value = conversationId;

      // Get user media
      localStream.value = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: false,
      });

      // Create peer connection
      peerConnection.value = new RTCPeerConnection(rtcConfig);

      // ICE connection state handler - more reliable for detecting disconnections
      peerConnection.value.oniceconnectionstatechange = () => {
        const state = peerConnection.value.iceConnectionState;
        if (
          state === 'disconnected' ||
          state === 'failed' ||
          state === 'closed'
        ) {
          if (!isTerminating.value) {
            endCall();
          }
        }
      };

      // Add local stream
      localStream.value.getTracks().forEach(track => {
        peerConnection.value.addTrack(track, localStream.value);
      });

      // Handle remote stream
      peerConnection.value.ontrack = event => {
        if (event.streams && event.streams[0]) {
          remoteStream.value = event.streams[0];
          playRemoteAudio();

          // If recording has already started, add remote stream to it
          addRemoteStreamToRecording();
        }
      };

      // Handle connection state
      peerConnection.value.onconnectionstatechange = () => {
        const state = peerConnection.value.connectionState;

        if (state === 'connected') {
          // WebRTC can reach 'connected' before callStatus is updated by the
          // async chain below (setLocalDescription → dispatch → callStatus='connected').
          // Set it here immediately so the timer/recording branch is never skipped.
          callStatus.value = 'connected';
          if (!timerStarted.value) {
            timerStarted.value = true;
            setTimeout(() => {
              if (callStatus.value === 'connected') {
                startCallTimer();
                if (!isRecording.value) startRecording();
              }
            }, 500);
          }
        } else if (
          state === 'disconnected' ||
          state === 'failed' ||
          state === 'closed'
        ) {
          if (!isTerminating.value) {
            endCall();
          }
        }
      };

      // Set remote description (offer from WhatsApp)
      await peerConnection.value.setRemoteDescription({
        type: 'offer',
        sdp: sdpOffer,
      });

      // Create answer
      const answer = await peerConnection.value.createAnswer();
      await peerConnection.value.setLocalDescription(answer);

      // Send answer to backend
      await store.dispatch('whatsappCalls/answerCall', {
        accountId,
        conversationId,
        callId,
        sdpAnswer: answer.sdp,
      });

      callStatus.value = 'connected';

      // Fallback: if onconnectionstatechange already fired 'connected' but
      // timerStarted wasn't set (e.g. callStatus was still 'connecting' then),
      // start now.
      if (!timerStarted.value && peerConnection.value?.connectionState === 'connected') {
        timerStarted.value = true;
        setTimeout(() => {
          if (callStatus.value === 'connected') {
            startCallTimer();
            if (!isRecording.value) startRecording();
          }
        }, 500);
      }

      return { success: true };
    } catch (error) {
      callStatus.value = 'idle';
      cleanup();
      return { success: false, error: error.message };
    }
  };

  /**
   * End active call
   * Terminates the call on WhatsApp side and cleans up local resources
   */
  async function endCall() {
    // Prevent multiple simultaneous calls to endCall
    if (isTerminating.value) {
      return;
    }

    isTerminating.value = true;

    try {
      // First, terminate on WhatsApp side to create the completed message
      if (currentCallId.value && callStatus.value !== 'ended') {
        try {
          const accountId = savedAccountId.value;
          const conversationId = savedConversationId.value;

          if (accountId && conversationId) {
            await store.dispatch('whatsappCalls/terminateCall', {
              accountId,
              callId: currentCallId.value,
              conversationId,
              duration: callDuration.value,
            });

            // Small delay to allow the synchronous termination message creation to propagate
            await sleep(500);
          }
        } catch (error) {
          String(error);
          // Continue with recording upload even if API call fails
        }
      }

      // Then stop recording and upload (this will find the message created above)
      await stopRecording();

      callStatus.value = 'ended';
      currentCallId.value = null;
      savedAccountId.value = null;
      savedConversationId.value = null;
      stopCallTimer();
      cleanup();
    } finally {
      // Always reset the flag, even if there's an error
      isTerminating.value = false;
    }
  }

  /**
   * Toggle mute/unmute
   */
  const toggleMute = () => {
    if (localStream.value) {
      const audioTrack = localStream.value.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled;
        isMuted.value = !audioTrack.enabled;
      }
    }
  };

  /**
   * Play remote audio
   */
  function playRemoteAudio() {
    if (remoteStream.value) {
      const audioElement = new Audio();
      audioElement.srcObject = remoteStream.value;
      audioElement.play().catch(() => null);
    }
  }

  /**
   * Start call duration timer
   */
  function startCallTimer() {
    callDuration.value = 0;
    callTimer = setInterval(() => {
      callDuration.value += 1;
    }, 1000);
  }

  /**
   * Stop call timer
   */
  function stopCallTimer() {
    if (callTimer) {
      clearInterval(callTimer);
      callTimer = null;
    }
  }

  /**
   * Cleanup resources
   */
  function cleanup() {
    // Note: Don't stop recording here - it should be stopped before cleanup
    // to ensure chunks are preserved and uploaded

    // Stop timer if running
    if (callTimer) {
      clearInterval(callTimer);
      callTimer = null;
    }

    // Close peer connection
    if (peerConnection.value) {
      peerConnection.value.close();
      peerConnection.value = null;
    }

    // Stop local stream
    if (localStream.value) {
      localStream.value.getTracks().forEach(track => track.stop());
      localStream.value = null;
    }

    // Clear remote stream
    remoteStream.value = null;
    isMuted.value = false;

    // Reset call state
    callStatus.value = 'idle';
    currentCallId.value = null;
    savedConversationId.value = null;
    savedAccountId.value = null;
    callDuration.value = 0;
    timerStarted.value = false;
    calleeAccepted.value = false;

    // Clean up audio context if not already closed
    if (
      recordingAudioContext.value &&
      recordingAudioContext.value.state !== 'closed'
    ) {
      recordingAudioContext.value.close();
      recordingAudioContext.value = null;
      recordingDestination.value = null;
      remoteSourceNode.value = null;
    }

    // Reset ICE candidate tracking
    sdpAnswerReceived = false;
    iceCandidatesQueue.length = 0;

    // Note: Don't reset recording state here - it's reset after upload in stopRecording->onstop->uploadRecording
  }

  /**
   * Format call duration as MM:SS
   */
  const formattedDuration = computed(() => {
    const minutes = Math.floor(callDuration.value / 60);
    const seconds = callDuration.value % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  });

  /**
   * Listen for call status changes from ActionCable
   * This is triggered when call status changes (ringing, connected, ended, etc.)
   */
  const setupCallStatusListener = () => {
    const handleCallStatusChanged = data => {
      // Only handle if it's our current call
      if (data.call_id !== currentCallId.value) {
        return;
      }

      // Handle status change
      const newStatus = data.status;

      // Status webhooks can arrive out-of-order relative to SDP/ICE.
      // We use ACCEPTED as the authoritative "callee answered" signal for outbound calls.
      if (newStatus === 'accepted') {
        calleeAccepted.value = true;

        // If WebRTC + SDP are already ready (out-of-order delivery), start now.
        maybeStartOutboundTimerAndRecording();
      }
    };

    const handleCallTerminated = data => {
      // Get current conversation ID
      const currentConversationId = store.getters.getSelectedChat?.id;

      // Only handle if it's our current conversation and we're in an active call
      if (
        data.conversation_id === currentConversationId &&
        callStatus.value !== 'idle'
      ) {
        callStatus.value = 'ended';
        stopCallTimer();

        // Emit event to close the widget
        emitter.emit('whatsapp-call-panel-close', {
          conversationId: currentConversationId,
          reason: 'terminated',
        });

        // Stop recording and wait for upload before cleanup
        stopRecording().then(() => {
          cleanup();
        });

        // Show notification to agent using mitt emitter
        emitter.emit('newToastMessage', {
          message: 'La llamada ha finalizado',
          type: 'info',
        });
      }
    };

    // Listen for SDP answer from WhatsApp (via webhook)
    const handleSdpAnswer = async data => {
      // Only apply if we're waiting for answer and this is our call
      if (!peerConnection.value || !currentCallId.value) {
        return;
      }

      if (sdpAnswerReceived) {
        return;
      }

      try {
        await peerConnection.value.setRemoteDescription({
          type: 'answer',
          sdp: data.sdpAnswer,
        });

        sdpAnswerReceived = true;

        // For outbound calls, SDP answer indicates the callee accepted, but media may not be connected yet.
        // Timer/recording will start when WebRTC transitions to a connected state.
        // (and when WhatsApp sends ACCEPTED)
        maybeStartOutboundTimerAndRecording();
      } catch (error) {
        String(error);
      }
    };

    // Subscribe to call events
    emitter.on('whatsapp_call_status_changed', handleCallStatusChanged);
    emitter.on('whatsapp_call_terminated', handleCallTerminated);
    emitter.on('whatsapp_call_sdp_answer', handleSdpAnswer);

    // Return cleanup function
    return () => {
      emitter.off('whatsapp_call_status_changed', handleCallStatusChanged);
      emitter.off('whatsapp_call_terminated', handleCallTerminated);
      emitter.off('whatsapp_call_sdp_answer', handleSdpAnswer);
    };
  };

  // Setup listener on mount
  const cleanupListener = setupCallStatusListener();

  // Cleanup on component unmount
  onUnmounted(() => {
    // Only call endCall if there's an active call (not already ended)
    if (callStatus.value !== 'idle' && callStatus.value !== 'ended') {
      endCall();
    }
    if (cleanupListener) {
      cleanupListener();
    }
  });

  return {
    // State
    callStatus,
    isMuted,
    callDuration,
    formattedDuration,
    localStream,
    remoteStream,
    isRecording,

    // Methods
    prepareMediaStream,
    initiateCall,
    answerCall,
    endCall,
    toggleMute,
  };
}
