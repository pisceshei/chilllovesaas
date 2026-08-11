# 所有 CHILL LOVE 背景工作的抽象基底。
#
# 後續 milestone 的租戶 job 必須以 shop_id 作為第一個參數，並在執行期間
# 明確建立 tenant context。見 docs/specs/11 §0、docs/specs/12 F4。
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
