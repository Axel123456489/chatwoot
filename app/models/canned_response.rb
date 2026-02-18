# == Schema Information
#
# Table name: canned_responses
#
#  id             :integer          not null, primary key
#  content        :text
#  content_type   :string           default("markdown"), not null
#  short_code     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :integer          not null
#  custom_role_id :bigint
#
# Indexes
#
#  index_canned_responses_on_account_id       (account_id)
#  index_canned_responses_on_content_trgm     (content) USING gin
#  index_canned_responses_on_content_type     (content_type)
#  index_canned_responses_on_custom_role_id   (custom_role_id)
#  index_canned_responses_on_short_code_trgm  (short_code) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (custom_role_id => custom_roles.id)
#

class CannedResponse < ApplicationRecord
  include Rails.application.routes.url_helpers

  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }
  validates :content_type, presence: true, inclusion: { in: %w[markdown plain_text] }

  belongs_to :account
  belongs_to :custom_role, optional: true
  has_many_attached :files

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }

  def file_base_data
    attachments = files.attachments

    attachments.map do |file|
      {
        id: file.id,
        canned_response_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: rails_blob_path(file, only_path: true),
        blob_id: file.blob_id,
        filename: file.filename.to_s,
        signed_id: file.blob.signed_id,
        byte_size: file.blob.byte_size
      }
    end
  end
end
