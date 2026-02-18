# Handles Mexico phone number normalization
#
# Mexico mobile numbers historically had a "1" prefix after the country code (521)
# for mobile numbers. This normalizer ensures consistency by always adding the "1"
# when it's missing, to match the format: 521 + area + number
#
# Examples:
#   52XXXXXXXXXX  → 521XXXXXXXXXX (adds the 1)
#   521XXXXXXXXXX → 521XXXXXXXXXX (unchanged)
class Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  def normalize(waid)
    return waid unless handles_country?(waid)

    # If already 13+ digits with 521 prefix, assume normalized
    return waid if waid.start_with?('521') && waid.length >= 13

    # Otherwise ensure the legacy mobile prefix "1" is present after country code
    waid.sub(/^52/, '521')
  end

  private

  def country_code_pattern
    /^52/
  end
end
