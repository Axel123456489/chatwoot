# frozen_string_literal: true

# Shim to ensure CustomRole is autoloadable in OSS runs where enterprise models
# live under enterprise/app/models. If the enterprise file is unavailable (e.g.
# stripped in OSS CI), fall back to a minimal stub so associations load.
unless defined?(CustomRole)
  enterprise_role_path = Rails.root.join('enterprise/app/models/custom_role.rb')

  begin
    raise LoadError unless enterprise_role_path.exist?

    require enterprise_role_path.to_s
  rescue LoadError
    # Minimal stub for OSS/CI without enterprise code
    class CustomRole < ApplicationRecord
      self.table_name = 'custom_roles'

      belongs_to :account, optional: true

      PERMISSIONS = [].freeze
    end
  end
end

# Ensure PERMISSIONS exists even if CustomRole was loaded elsewhere without it
CustomRole.const_set(:PERMISSIONS, [].freeze) unless CustomRole.const_defined?(:PERMISSIONS)
