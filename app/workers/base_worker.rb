class BaseWorker
  include Sidekiq::Worker

  def slack_notify(error, jid, parent_message_ts = nil)
    bot = ::Genova::Slack::Bot.new(parent_message_ts: parent_message_ts)
    bot.post_error(
      error: error,
      deploy_job_id: jid
    )
  end
end