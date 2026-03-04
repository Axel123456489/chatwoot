class DisableReportRollupForAllAccounts < ActiveRecord::Migration[7.1]
  def up
    report_rollup_bit = 524_288
    Account.where('((feature_flags)::bigint & ?) = ?', report_rollup_bit, report_rollup_bit).find_each(batch_size: 100) do |account|
      account.disable_features(:report_rollup)
      account.save!(validate: false)
    end
  end
end
