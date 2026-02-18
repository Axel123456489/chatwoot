import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import TemplatesHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'templates_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'templates_list',
          meta: {
            // Restrict access to administrators only
            permissions: ['administrator'],
          },
          component: TemplatesHome,
        },
      ],
    },
  ],
};
