# frozen_string_literal: true

FactoryBot.define do
  factory :canned_response do
    content { 'Content' }
    sequence(:short_code) { |n| "CODE#{n}" }
    account
    custom_role { nil } # Optional association with custom_role
  end
end
