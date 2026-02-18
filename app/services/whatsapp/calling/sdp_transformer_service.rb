# frozen_string_literal: true

# Transform WhatsApp SDP to be compatible with browser's offer
# Key transformations:
# - Match m-line IDs (mid) from browser offer
# - Preserve media types and codec compatibility
class Whatsapp::Calling::SdpTransformerService
  include Whatsapp::Calling::Concerns::Loggable

  def initialize(browser_offer:, whatsapp_answer:)
    @browser_offer = browser_offer
    @whatsapp_answer = whatsapp_answer
  end

  def transform_for_browser
    return nil if @whatsapp_answer.blank?

    browser_mid = extract_mid_from_offer(@browser_offer)
    transformed_sdp = @whatsapp_answer.dup

    transformed_sdp = replace_mid_in_answer(transformed_sdp, browser_mid)
    transformed_sdp = replace_bundle_group(transformed_sdp, browser_mid)

    log_info('SDP transformed', browser_mid: browser_mid)
    transformed_sdp
  end

  private

  def extract_mid_from_offer(sdp)
    # Find the first m= line's mid attribute
    # Example: a=mid:0 or a=mid:audio
    mid_line = sdp.lines.find { |line| line.strip.start_with?('a=mid:') }
    return '0' unless mid_line # Default to '0' if not found

    mid_line.strip.sub('a=mid:', '')
  end

  def replace_mid_in_answer(sdp, new_mid)
    # Replace mid values in SDP answer (match only to end of line, not entire string)
    sdp.gsub(/^a=mid:[^\r\n]+/, "a=mid:#{new_mid}")
  end

  def replace_bundle_group(sdp, new_mid)
    # Replace BUNDLE group to match the new mid
    # Example: "a=group:BUNDLE audio" -> "a=group:BUNDLE 0"
    sdp.gsub(/^a=group:BUNDLE\s+[^\r\n]+/, "a=group:BUNDLE #{new_mid}")
  end
end
