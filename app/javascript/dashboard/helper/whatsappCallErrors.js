/**
 * WhatsApp Calling Error Codes and Messages
 * Maps backend/WhatsApp errors to user-friendly messages
 */

export const ERROR_CODES = {
  // Backend/Server Errors
  SDP_GENERATION_FAILED: 'sdp_generation_failed',
  MEDIA_SERVER_TIMEOUT: 'media_server_timeout',

  // WhatsApp API Errors
  CALLING_NOT_ENABLED: 'calling_api_not_enabled',
  INVALID_PHONE_NUMBER: 'invalid_phone_number',
  RATE_LIMIT_EXCEEDED: 'rate_limit_exceeded',
  PERMISSION_DENIED: 'permission_denied',
  PHONE_NUMBER_BLOCKED: 'phone_number_blocked',
  RECIPIENT_UNAVAILABLE: 'recipient_unavailable',

  // Network/Connection Errors
  NETWORK_ERROR: 'network_error',
  CONNECTION_TIMEOUT: 'connection_timeout',
  ICE_CONNECTION_FAILED: 'ice_connection_failed',

  // Call State Errors
  CALL_ALREADY_ACTIVE: 'call_already_active',
  NO_ACTIVE_CALL: 'no_active_call',
  CALL_NOT_FOUND: 'call_not_found',

  // Permission Errors
  MICROPHONE_PERMISSION_DENIED: 'microphone_permission_denied',
  DAILY_LIMIT_REACHED: 'daily_limit_reached',
  ACCOUNT_NOT_AUTHORIZED: 'account_not_authorized',

  // Generic
  UNKNOWN_ERROR: 'unknown_error',
};

export const ERROR_MESSAGES = {
  [ERROR_CODES.SDP_GENERATION_FAILED]: {
    title: 'Call Setup Failed',
    message: 'Failed to set up the call. Please try again in a moment.',
    retryable: true,
    severity: 'error',
  },
  [ERROR_CODES.MEDIA_SERVER_TIMEOUT]: {
    title: 'Request Timeout',
    message: 'The media server took too long to respond. Please try again.',
    retryable: true,
    severity: 'warning',
  },
  [ERROR_CODES.CALLING_NOT_ENABLED]: {
    title: 'WhatsApp Calling Not Available',
    message:
      'WhatsApp calling is not enabled for this account. Please contact Meta support to enable the Calling API.',
    retryable: false,
    severity: 'critical',
  },
  [ERROR_CODES.INVALID_PHONE_NUMBER]: {
    title: 'Invalid Phone Number',
    message: 'The phone number is invalid or not registered on WhatsApp.',
    retryable: false,
    severity: 'error',
  },
  [ERROR_CODES.RATE_LIMIT_EXCEEDED]: {
    title: 'Rate Limit Exceeded',
    message:
      'Too many call attempts. Please wait a few minutes before trying again.',
    retryable: true,
    severity: 'warning',
  },
  [ERROR_CODES.PERMISSION_DENIED]: {
    title: 'Permission Required',
    message:
      'You need permission from the contact before making a call. Request permission first.',
    retryable: false,
    severity: 'warning',
  },
  [ERROR_CODES.PHONE_NUMBER_BLOCKED]: {
    title: 'Contact Blocked',
    message: 'This contact has blocked calls from your business.',
    retryable: false,
    severity: 'error',
  },
  [ERROR_CODES.RECIPIENT_UNAVAILABLE]: {
    title: 'Recipient Unavailable',
    message: 'The recipient is not available to receive calls right now.',
    retryable: true,
    severity: 'warning',
  },
  [ERROR_CODES.NETWORK_ERROR]: {
    title: 'Network Error',
    message: 'A network error occurred. Please check your internet connection.',
    retryable: true,
    severity: 'error',
  },
  [ERROR_CODES.CONNECTION_TIMEOUT]: {
    title: 'Connection Timeout',
    message: 'The connection timed out. Please try again.',
    retryable: true,
    severity: 'warning',
  },
  [ERROR_CODES.ICE_CONNECTION_FAILED]: {
    title: 'Connection Failed',
    message: 'Failed to establish media connection. Check firewall settings.',
    retryable: true,
    severity: 'error',
  },
  [ERROR_CODES.CALL_ALREADY_ACTIVE]: {
    title: 'Call In Progress',
    message:
      'There is already an active call. End it before starting a new one.',
    retryable: false,
    severity: 'warning',
  },
  [ERROR_CODES.NO_ACTIVE_CALL]: {
    title: 'No Active Call',
    message: 'There is no active call to perform this action.',
    retryable: false,
    severity: 'warning',
  },
  [ERROR_CODES.CALL_NOT_FOUND]: {
    title: 'Call Not Found',
    message: 'The call session could not be found.',
    retryable: false,
    severity: 'error',
  },
  [ERROR_CODES.MICROPHONE_PERMISSION_DENIED]: {
    title: 'Microphone Access Denied',
    message:
      'Please allow microphone access in your browser settings to make calls.',
    retryable: false,
    severity: 'error',
  },
  [ERROR_CODES.DAILY_LIMIT_REACHED]: {
    title: 'Daily Limit Reached',
    message:
      'You have reached the daily limit for WhatsApp calls. Try again tomorrow.',
    retryable: false,
    severity: 'warning',
  },
  [ERROR_CODES.ACCOUNT_NOT_AUTHORIZED]: {
    title: 'Not Authorized',
    message: 'Your account is not authorized to make WhatsApp calls.',
    retryable: false,
    severity: 'critical',
  },
  [ERROR_CODES.UNKNOWN_ERROR]: {
    title: 'Unexpected Error',
    message: 'An unexpected error occurred. Please try again.',
    retryable: true,
    severity: 'error',
  },
};

/**
 * Parse error from backend response and map to error code
 * @param {Error|Object} error - Error object from API or exception
 * @returns {string} Error code
 */
export const parseErrorCode = error => {
  // Check if it's an API response error
  if (error.response?.data?.error) {
    const errorMessage = error.response.data.error.toLowerCase();

    // Map common error messages to codes
    if (
      errorMessage.includes('calling api not enabled') ||
      errorMessage.includes('calling not enabled')
    ) {
      return ERROR_CODES.CALLING_NOT_ENABLED;
    }
    if (
      errorMessage.includes('sdp') ||
      errorMessage.includes('failed to generate')
    ) {
      return ERROR_CODES.SDP_GENERATION_FAILED;
    }
    if (errorMessage.includes('timeout')) {
      return ERROR_CODES.MEDIA_SERVER_TIMEOUT;
    }
    if (errorMessage.includes('invalid') && errorMessage.includes('phone')) {
      return ERROR_CODES.INVALID_PHONE_NUMBER;
    }
    if (
      errorMessage.includes('rate limit') ||
      errorMessage.includes('too many')
    ) {
      return ERROR_CODES.RATE_LIMIT_EXCEEDED;
    }
    if (errorMessage.includes('permission')) {
      return ERROR_CODES.PERMISSION_DENIED;
    }
    if (errorMessage.includes('blocked')) {
      return ERROR_CODES.PHONE_NUMBER_BLOCKED;
    }
    if (errorMessage.includes('unavailable')) {
      return ERROR_CODES.RECIPIENT_UNAVAILABLE;
    }
    if (
      errorMessage.includes('already active') ||
      errorMessage.includes('call in progress')
    ) {
      return ERROR_CODES.CALL_ALREADY_ACTIVE;
    }
    if (errorMessage.includes('no active call')) {
      return ERROR_CODES.NO_ACTIVE_CALL;
    }
    if (errorMessage.includes('not found')) {
      return ERROR_CODES.CALL_NOT_FOUND;
    }
    if (errorMessage.includes('daily limit')) {
      return ERROR_CODES.DAILY_LIMIT_REACHED;
    }
    if (errorMessage.includes('not authorized')) {
      return ERROR_CODES.ACCOUNT_NOT_AUTHORIZED;
    }
  }

  // Check for network errors
  if (
    error.message?.includes('Network Error') ||
    error.code === 'ERR_NETWORK'
  ) {
    return ERROR_CODES.NETWORK_ERROR;
  }

  if (error.code === 'ECONNABORTED' || error.message?.includes('timeout')) {
    return ERROR_CODES.CONNECTION_TIMEOUT;
  }

  // Check for microphone permission error
  if (
    error.name === 'NotAllowedError' ||
    error.message?.includes('microphone')
  ) {
    return ERROR_CODES.MICROPHONE_PERMISSION_DENIED;
  }

  // Default unknown error
  return ERROR_CODES.UNKNOWN_ERROR;
};

/**
 * Get error details for a given error
 * @param {Error|Object} error - Error object
 * @returns {Object} Error details with title, message, retryable, severity
 */
export const getErrorDetails = error => {
  const errorCode = parseErrorCode(error);
  const details =
    ERROR_MESSAGES[errorCode] || ERROR_MESSAGES[ERROR_CODES.UNKNOWN_ERROR];

  return {
    code: errorCode,
    ...details,
    originalError: error,
  };
};

/**
 * Check if an error is retryable
 * @param {Error|Object} error - Error object
 * @returns {boolean} Whether the error is retryable
 */
export const isRetryableError = error => {
  const errorCode = parseErrorCode(error);
  return ERROR_MESSAGES[errorCode]?.retryable || false;
};

/**
 * Get user-friendly error message
 * @param {Error|Object} error - Error object
 * @returns {string} User-friendly error message
 */
export const getErrorMessage = error => {
  const details = getErrorDetails(error);
  return details.message;
};

/**
 * Get error title
 * @param {Error|Object} error - Error object
 * @returns {string} Error title
 */
export const getErrorTitle = error => {
  const details = getErrorDetails(error);
  return details.title;
};

/**
 * Log error to console with details
 * @param {string} context - Context where error occurred
 * @param {Error|Object} error - Error object
 */
export const logError = () => {};
