# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#
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
