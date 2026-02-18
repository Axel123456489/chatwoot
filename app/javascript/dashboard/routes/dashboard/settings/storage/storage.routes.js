import { frontendURL } from '../../../../helper/URLHelper';

const SettingsContent = () => import('./Wrapper.vue');
const Index = () => import('./Index.vue');

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/storage'),
      component: SettingsContent,
      props: () => {
        return {
          headerTitle: 'STORAGE_MGMT.TITLE',
          icon: 'server',
          showBackButton: true,
        };
      },
      children: [
        {
          path: '',
          name: 'storage_settings',
          meta: {
            permissions: ['administrator'],
          },
          component: Index,
        },
      ],
    },
  ],
};
