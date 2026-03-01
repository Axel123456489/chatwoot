<script setup>
import { computed, ref, watch, useAttrs } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { useCallsStore } from 'dashboard/stores/calls';
import whatsappCallsAPI from 'dashboard/api/whatsapp/calls';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  phone: { type: String, default: '' },
  contactId: { type: [String, Number], required: true },
  conversationInboxId: { type: [String, Number], default: null }, // Inbox ID from conversation
  label: { type: String, default: '' },
  icon: { type: [String, Object, Function], default: 'i-lucide-phone' },
  size: { type: String, default: 'sm' },
  tooltipLabel: { type: String, default: '' },
});

defineOptions({ inheritAttrs: false });
const attrs = useAttrs();
const route = useRoute();
const router = useRouter();
const store = useStore();

const { t } = useI18n();

const dialogRef = ref(null);

const inboxesList = useMapGetter('inboxes/getInboxes');
const contactsUiFlags = useMapGetter('contacts/getUIFlags');

// Filter WhatsApp inboxes that have calling enabled
const whatsappInboxes = computed(() => {
  const allInboxes = inboxesList.value || [];
  let filtered = allInboxes.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP &&
      inbox.calling_enabled === true
  );

  // If we're in a conversation context, only show that specific inbox if it has calling enabled
  if (props.conversationInboxId) {
    filtered = filtered.filter(inbox => inbox.id === props.conversationInboxId);
  }

  return filtered;
});
const hasWhatsAppInboxes = computed(() => whatsappInboxes.value.length > 0);

// Hide when no phone or no WhatsApp calling-enabled inboxes
const shouldRender = computed(() => hasWhatsAppInboxes.value && !!props.phone);

const isInitiatingCall = computed(() => {
  return contactsUiFlags.value?.isInitiatingWhatsAppCall || false;
});

// Per-contact call permission fetched from the API
const permission = ref(null);
const permissionLoaded = ref(false);

const loadPermission = async () => {
  const inbox = whatsappInboxes.value[0];
  if (!inbox || !props.contactId) return;
  permissionLoaded.value = false;
  try {
    const { data } = await whatsappCallsAPI.getPermission({
      contactId: props.contactId,
      inboxId: inbox.id,
    });
    permission.value = data.permission ?? null;
  } catch {
    permission.value = null;
  } finally {
    permissionLoaded.value = true;
  }
};

// immediate: true fires as soon as inboxes are available, even before mount.
// Watching both inbox id and contactId covers inbox picker changes.
watch(
  () => [whatsappInboxes.value[0]?.id, props.contactId],
  loadPermission,
  { immediate: true }
);

// Derive status from the per-contact permission record (expires_at from the permission,
// not the global calling_expiry_date on the inbox calling_config).
const callingWindowStatus = computed(() => {
  const perm = permission.value;
  if (!perm || !perm.granted) return 'not_granted';
  if (!perm.expires_at) return 'permanent';
  const daysLeft = Math.ceil(
    (new Date(perm.expires_at) - new Date()) / (1000 * 60 * 60 * 24)
  );
  if (daysLeft < 0) return 'expired';
  if (daysLeft <= 7) return 'expiring_soon';
  return 'temporary';
});

const callingWindowTooltip = computed(() => {
  const base = props.tooltipLabel || t('CONTACT_PANEL.WHATSAPP_CALL');
  const perm = permission.value;
  if (!perm || !perm.granted || !perm.expires_at) return base;
  const expiry = new Date(perm.expires_at);
  const formatted = expiry.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
  const daysLeft = Math.ceil((expiry - new Date()) / (1000 * 60 * 60 * 24));
  if (daysLeft < 0) return t('CONTACT_PANEL.WHATSAPP_CALL_EXPIRED', { date: formatted });
  if (daysLeft === 0) return t('CONTACT_PANEL.WHATSAPP_CALL_EXPIRES_TODAY');
  if (daysLeft <= 7) return t('CONTACT_PANEL.WHATSAPP_CALL_EXPIRES_SOON', { days: daysLeft, date: formatted });
  return `${base} · ${t('CONTACT_PANEL.WHATSAPP_CALL_UNTIL', { date: formatted })}`;
});

const STATUS_DOT_CLASSES = {
  permanent: 'bg-n-teal-9',
  temporary: 'bg-n-teal-9',
  expiring_soon: 'bg-n-amber-9 animate-pulse',
  expired: 'bg-n-ruby-9',
  not_granted: 'bg-n-slate-9',
};
const statusDotClass = computed(
  () => STATUS_DOT_CLASSES[callingWindowStatus.value] ?? 'bg-n-slate-7'
);

const isCallDisabled = computed(() => {
  if (isInitiatingCall.value) return true;
  // Disable when the permission record says calls can't be made
  if (permission.value && !permission.value.can_make_call) return true;
  return false;
});

const navigateToConversation = conversationId => {
  const accountId = route.params.accountId;
  if (conversationId && accountId) {
    const path = frontendURL(
      conversationUrl({
        accountId,
        id: conversationId,
      })
    );
    router.push({ path });
  }
};

const startCall = async inboxId => {
  if (isInitiatingCall.value) return;

  try {
    const response = await store.dispatch('contacts/initiateWhatsAppCall', {
      contactId: props.contactId,
      inboxId,
      phoneNumber: props.phone,
    });

    const { call_id: callId, conversation_id: conversationId } = response;

    // Add call to store immediately so widget shows
    const callsStore = useCallsStore();
    callsStore.addCall({
      callSid: callId,
      conversationId,
      inboxId,
      callDirection: 'outbound',
      channelType: 'whatsapp', // Identificar como llamada de WhatsApp
    });

    useAlert(t('CONTACT_PANEL.WHATSAPP_CALL_INITIATED'));
    navigateToConversation(conversationId);
  } catch (error) {
    const apiError = error?.message;
    useAlert(apiError || t('CONTACT_PANEL.WHATSAPP_CALL_FAILED'));
  }
};

const onClick = async () => {
  if (whatsappInboxes.value.length > 1) {
    dialogRef.value?.open();
    return;
  }
  const [inbox] = whatsappInboxes.value;
  await startCall(inbox.id);
};

const onPickInbox = async inbox => {
  dialogRef.value?.close();
  await startCall(inbox.id);
};
</script>

<template>
  <span class="contents">
    <span v-if="shouldRender" class="relative inline-flex">
      <Button
        v-tooltip.top-end="callingWindowTooltip"
        v-bind="attrs"
        :disabled="isCallDisabled"
        :is-loading="isInitiatingCall"
        :label="label"
        :icon="icon"
        :size="size"
        @click="onClick"
      />
      <span
        v-if="permissionLoaded"
        class="absolute -top-0.5 -right-0.5 size-2 rounded-full ring-1 ring-n-surface-1"
        :class="statusDotClass"
      />
    </span>

    <Dialog
      v-if="shouldRender && whatsappInboxes.length > 1"
      ref="dialogRef"
      :title="$t('CONTACT_PANEL.WHATSAPP_INBOX_PICKER.TITLE')"
      show-cancel-button
      :show-confirm-button="false"
      width="md"
    >
      <div class="flex flex-col gap-2">
        <button
          v-for="inbox in whatsappInboxes"
          :key="inbox.id"
          type="button"
          class="flex items-center justify-between w-full px-4 py-2 text-left rounded-lg hover:bg-n-alpha-2"
          @click="onPickInbox(inbox)"
        >
          <div class="flex items-center gap-2">
            <span class="i-logos-whatsapp-icon text-lg" />
            <span class="text-sm text-n-slate-12">{{ inbox.name }}</span>
          </div>
          <span v-if="inbox.phone_number" class="text-xs text-n-slate-10">
            {{ inbox.phone_number }}
          </span>
        </button>
      </div>
    </Dialog>
  </span>
</template>
