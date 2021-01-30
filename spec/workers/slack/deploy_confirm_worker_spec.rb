require 'rails_helper'

module Slack
  describe DeployConfirmWorker do
    describe 'perform' do
      let(:bot_mock) { double(Genova::Slack::Interactive::Bot) }

      include_context :session_start

      before do
        allow(bot_mock).to receive(:ask_confirm_deploy)
        allow(Genova::Slack::Interactive::Bot).to receive(:new).and_return(bot_mock)

        subject.perform(id)
      end

      it 'should be in queeue' do
        is_expected.to be_processed_in(:slack_deploy_confirm)
      end

      it 'should be no retry' do
        is_expected.to be_retryable(false)
      end
    end
  end
end
