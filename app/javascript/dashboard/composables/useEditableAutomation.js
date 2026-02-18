import useAutomationValues from './useAutomationValues';

import {
  getCustomAttributeInputType,
  filterCustomAttributes,
  getStandardAttributeInputType,
  isCustomAttribute,
} from 'dashboard/helper/automationHelper';

export function useEditableAutomation() {
  const { getConditionDropdownValues, getActionDropdownValues } =
    useAutomationValues();

  /**
   * This function sets the conditions for automation.
   * It help to format the conditions for the automation when we open the edit automation modal.
   * @param {Object} automation - The automation object containing conditions to manifest.
   * @param {Array} allCustomAttributes - List of all custom attributes.
   * @param {Object} automationTypes - Object containing automation type definitions.
   * @returns {Array} An array of manifested conditions.
   */
  const manifestConditions = (
    automation,
    allCustomAttributes,
    automationTypes
  ) => {
    const customAttributes = filterCustomAttributes(allCustomAttributes);
    return automation.conditions.map(condition => {
      const customAttr = isCustomAttribute(
        customAttributes,
        condition.attribute_key
      );
      let inputType = 'plain_text';
      if (customAttr) {
        inputType = getCustomAttributeInputType(customAttr.type);
      } else {
        inputType = getStandardAttributeInputType(
          automationTypes,
          automation.event_name,
          condition.attribute_key
        );
      }

      // Special handling for attribute_changed operator
      if (condition.filter_operator === 'attribute_changed') {
        const values = condition.values || {};

        // For date type, UI expects string values (not arrays)
        if (inputType === 'date') {
          const from = Array.isArray(values.from)
            ? values.from[0] || ''
            : values.from || '';
          const to = Array.isArray(values.to)
            ? values.to[0] || ''
            : values.to || '';
          return {
            ...condition,
            query_operator: condition.query_operator || 'and',
            values: { from, to },
          };
        }

        // For dropdowns, UI expects arrays of option objects for from/to
        if (inputType === 'multi_select' || inputType === 'search_select') {
          const options = [
            ...getConditionDropdownValues(condition.attribute_key),
          ];
          const mapIdsToOptions = arr => {
            const ids = Array.isArray(arr)
              ? arr.map(v => (v === null ? '__NONE__' : v))
              : [];
            return options.filter(opt => ids.includes(opt.id));
          };
          return {
            ...condition,
            query_operator: condition.query_operator || 'and',
            values: {
              from: mapIdsToOptions(values.from),
              to: mapIdsToOptions(values.to),
            },
          };
        }

        // Fallback for any other input types
        return {
          ...condition,
          query_operator: condition.query_operator || 'and',
          values,
        };
      }

      if (inputType === 'plain_text' || inputType === 'date') {
        return { ...condition, values: condition.values[0] };
      }
      if (inputType === 'comma_separated_plain_text') {
        return { ...condition, values: condition.values.join(',') };
      }
      return {
        ...condition,
        query_operator: condition.query_operator || 'and',
        values: [...getConditionDropdownValues(condition.attribute_key)].filter(
          item => [...condition.values].includes(item.id)
        ),
      };
    });
  };

  /**
   * Generates an array of actions for the automation.
   * @param {Object} action - The action object.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Array|Object} Generated actions array or object based on input type.
   */
  const generateActionsArray = (action, automationActionTypes) => {
    const params = action.action_params;
    const inputType = automationActionTypes.find(
      item => item.key === action.action_name
    ).inputType;
    if (inputType === 'multi_select' || inputType === 'search_select') {
      return [...getActionDropdownValues(action.action_name)].filter(item =>
        [...params].includes(item.id)
      );
    }
    if (inputType === 'team_message') {
      return {
        team_ids: [...getActionDropdownValues(action.action_name)].filter(
          item => [...params[0].team_ids].includes(item.id)
        ),
        message: params[0].message,
      };
    }
    return [...params];
  };

  /**
   * This function sets the actions for automation.
   * It help to format the actions for the automation when we open the edit automation modal.
   * @param {Object} automation - The automation object containing actions.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Array} An array of manifested actions.
   */
  const manifestActions = (automation, automationActionTypes) => {
    return automation.actions.map(action => ({
      ...action,
      action_params: action.action_params.length
        ? generateActionsArray(action, automationActionTypes)
        : [],
    }));
  };

  /**
   * Formats the automation object for use when we edit the automation.
   * It help to format the conditions and actions for the automation when we open the edit automation modal.
   * @param {Object} automation - The automation object to format.
   * @param {Array} allCustomAttributes - List of all custom attributes.
   * @param {Object} automationTypes - Object containing automation type definitions.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Object} A new object with formatted automation data, including automation conditions and actions.
   */
  const formatAutomation = (
    automation,
    allCustomAttributes,
    automationTypes,
    automationActionTypes
  ) => {
    return {
      ...automation,
      conditions: manifestConditions(
        automation,
        allCustomAttributes,
        automationTypes
      ),
      actions: manifestActions(automation, automationActionTypes),
    };
  };

  return { formatAutomation };
}
