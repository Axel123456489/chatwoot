# Ensure new accounts start with all features enabled by default,
# while still allowing per-account overrides from Super Admin.

Rails.application.config.after_initialize do
  config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
  next unless config&.value.is_a?(Array)

  updated = config.value.map do |feature|
    # normalize keys to strings to avoid symbol/hash mismatches
    f = feature.stringify_keys
    f['enabled'] = true
    f
  end

  # Only update if there is any difference to avoid unnecessary writes
  config.update(value: updated) if updated.to_s != config.value.to_s
rescue StandardError => e
  Rails.logger.error("Failed to update ACCOUNT_LEVEL_FEATURE_DEFAULTS: #{e.message}")
end
