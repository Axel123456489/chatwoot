# Provide a minimal Stripe Billing namespace when the SDK version lacks it
module Stripe; end unless defined?(Stripe)
module Stripe::Billing; end unless defined?(Stripe::Billing)

unless defined?(Stripe::Billing::CreditGrant)
  class Stripe::Billing::CreditGrant
    class << self
      def create(*); end
    end
  end
end

if defined?(Stripe::Billing::CreditGrant) && !Stripe::Billing::CreditGrant.respond_to?(:create)
  class << Stripe::Billing::CreditGrant
    def create(*); end
  end
end
