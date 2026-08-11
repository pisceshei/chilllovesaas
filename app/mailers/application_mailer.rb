# 所有 CHILL LOVE 郵件的抽象基底。
#
# @see docs/specs/11-production-baseline.md §0
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
