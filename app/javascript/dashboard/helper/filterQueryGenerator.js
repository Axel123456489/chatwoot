const setArrayValues = item => {
  return item.values[0]?.id ? item.values.map(val => val.id) : item.values;
};

// Normalize values for attribute_changed operator to shape: { from: [...], to: [...] }
const normalizeAttributeChangedValues = item => {
  const v = item.values || {};

  const mapToComparable = val => {
    // Convert value objects to ids, and special sentinel to null
    if (val && typeof val === 'object' && 'id' in val) {
      return val.id === '__NONE__' ? null : val.id;
    }
    return val === '__NONE__' ? null : val;
  };

  const normalize = val => {
    if (Array.isArray(val)) {
      return val.map(mapToComparable);
    }
    if (val === undefined || val === null || val === '') {
      return [];
    }
    return [mapToComparable(val)];
  };

  return {
    from: normalize(v.from),
    to: normalize(v.to),
  };
};

const generateValues = item => {
  // Special handling for attribute_changed to preserve { from, to }
  if (item.filter_operator === 'attribute_changed') {
    return normalizeAttributeChangedValues(item);
  }
  if (item.attribute_key === 'content') {
    const values = item.values || '';
    return values.split(',');
  }
  if (Array.isArray(item.values)) {
    return setArrayValues(item);
  }
  if (typeof item.values === 'object') {
    return [item.values.id];
  }
  if (!item.values) {
    return [];
  }
  return [item.values];
};

const generatePayload = data => {
  // Make a copy of data to avoid vue data reactivity issues
  const filters = JSON.parse(JSON.stringify(data));
  let payload = filters.map(item => {
    // If item key is content, we will split it using comma and return as array
    // FIX ME: Make this generic option instead of using the key directly here
    item.values = generateValues(item);
    return item;
  });

  // For every query added, the query_operator is set default to and so the
  // last query will have an extra query_operator, this would break the api.
  // Setting this to null for all query payload
  payload[payload.length - 1].query_operator = undefined;
  return { payload };
};

export default generatePayload;
