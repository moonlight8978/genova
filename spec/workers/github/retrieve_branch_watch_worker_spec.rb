require 'rails_helper'

module Github
  describe RetrieveBranchWatchWorker do
    describe 'perform' do
      let(:jid) { Time.new.utc.to_i }
      let(:workers_mock) { double(Sidekiq::Workers) }
      let(:bot_mock) { double(Genova::Slack::Interactive::Bot) }
      let(:session_store_mock) { double(Genova::Slack::SessionStore) }

      before do
        stub_const('Github::RetrieveBranchWatchWorker::WAIT_INTERVAL', 1)
        stub_const('Github::RetrieveBranchWatchWorker::NOTIFY_THRESHOLD', 1)

        allow(session_store_mock).to receive(:params).and_return(retrieve_branch_jid: 'retrieve_branch_jid')
        allow(Genova::Slack::SessionStore).to receive(:new).and_return(session_store_mock)

        allow(workers_mock).to receive(:each).and_yield(
          'process_id',
          'thread_id',
          'payload' =>  { 'jid': jid }
        )
        allow(Sidekiq::Workers).to receive(:new).and_return(workers_mock)

        allow(bot_mock).to receive(:send_message)
        allow(Genova::Slack::Interactive::Bot).to receive(:new).and_return(bot_mock)

        subject.perform(jid)
      end

      it 'should be in queue' do
        is_expected.to be_processed_in(:github_retrieve_branch_watch)
      end

      it 'should be no retry' do
        is_expected.to be_retryable(false)
      end
    end
  end
end
