<script>
import { mapGetters } from 'vuex';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  components: {
    SettingsWrapper,
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
    backUrl() {
      return `/app/accounts/${this.accountId}/settings/general`;
    },
  },
};
</script>

<template>
  <SettingsWrapper
    :header-title="$t('STORAGE_MGMT.TITLE')"
    icon="server"
    :back-url="backUrl"
  >
    <router-view />
  </SettingsWrapper>
</template>
