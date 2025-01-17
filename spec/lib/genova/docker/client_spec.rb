require 'rails_helper'

module Genova
  module Docker
    describe Client do
      describe 'build_image' do
        let(:cipher_mock) { double(Utils::Cipher) }
        let(:code_manager_mock) { double(CodeManager::Git) }
        let(:docker_client) { Genova::Docker::Client.new(code_manager_mock) }

        it 'should be return repository name' do
          allow(code_manager_mock).to receive(:base_path).and_return('.')
          allow(Utils::Cipher).to receive(:new).and_return(cipher_mock)

          container_config = {
            name: 'web',
            build: '.'
          }

          allow(File).to receive(:file?).and_return(true)

          executor_mock = double(Command::Executor)
          allow(executor_mock).to receive(:command)
          allow(Command::Executor).to receive(:new).and_return(executor_mock)

          allow(::Docker::Image).to receive(:all).and_return(foo: 'bar')

          expect(docker_client.build_image(container_config, 'account_id.dkr.ecr.ap-northeast-1.amazonaws.com/web:latest')).to eq('web')
        end
      end
    end
  end
end
