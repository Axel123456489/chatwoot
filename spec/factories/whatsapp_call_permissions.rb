# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_call_permission, class: 'Whatsapp::CallPermission' do
    account
    contact { association :contact, account: account }
    inbox do
      association :inbox, account: account, channel: build(:channel_whatsapp, account: account)
    end
    phone_number_id { inbox.channel.phone_number_id }
    status { 'pending' }
    remaining_calls { 0 }
    metadata { {} }

    trait :granted do
      status { 'granted' }
      granted_at { Time.current }
      remaining_calls { WhatsappCallPermission::DAILY_CALL_LIMIT }
    end

    trait :pending_recent do
      status { 'pending' }
      requested_at { 1.hour.ago }
    end

    trait :pending_old do
      status { 'pending' }
      requested_at { 25.hours.ago }
    end
  end
end
