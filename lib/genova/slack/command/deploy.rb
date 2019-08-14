module Genova
  module Slack
    module Command
      class Deploy < SlackRubyBot::Commands::Base
        command 'deploy'
        command 'deploy:service'
        command 'deploy:run-task'
        command 'deploy:scheduled-task'

        class << self
          def call(client, data, match)
            logger.info("Execute deploy command: (UNAME: #{client.owner}, user=#{data.user})")
            logger.info("Input command: #{match['command']} #{match['expression']}")

            bot = Genova::Slack::Bot.new(client.web_client)

            begin
              type = case match['command'].split(':')[1]
                when 'run-task'
                  DeployJob.type.find_value(:run_task) 
                when 'scheduled-task'
                  DeployJob.type.find_value(:scheduled_task) 
                else
                  DeployJob.type.find_value(:service) 
              end

              if match['expression'].blank?
                bot.post_choose_repository
              else
                expressions = match['expression'].split(' ')
                results = send("parse_#{type}", expressions)

                bot.post_confirm_deploy(
                  type: type,
                  account: results[:account],
                  repository: results[:repository],
                  branch: results[:branch],
                  cluster: results[:cluster],
                  run_task: results[:run_task],
                  service: results[:service],
                  scheduled_task_rule: results[:scheduled_task_rule],
                  scheduled_task_target: results[:scheduled_task_target],
                  confirm: true
                )
              end
            rescue => e
              logger.error(e)

              bot.post_error(
                error: e,
                slack_user_id: data.user
              )
            end
          end

          private

          def parse_run_task(expressions)
            validations = {
              :account => String,
              :repository => String,
              :branch => String,
              :cluster => String,
              :run_task => String
            }

            values = parse_expressions(expressions)
            validate(values, validations)
            values
          end

          def parse_service(expressions)
            validations = {
              :account => String,
              :repository => String,
              :branch => String,
              :cluster => String,
              :service => String
            }

            values = parse_expressions(expressions)
            validate(values, validations)
            values
          end

          def parse_scheduled_task(expressions)
            validations = {
              :account => String,
              :repository => String,
              :branch => String,
              :cluster => String,
              :scheduled_task_rule => String,
              :scheduled_task_target => String
            }

            values = parse_expressions(expressions)
            validate(values, validations)
            values
          end

          def validate(values, validations)
            validator = HashValidator.validate(values, validations)
            raise InvalidArgumentError, "#{validator.errors.keys[0]}: #{validator.errors.values[0]}" unless validator.valid?
          end

          def parse_expressions(expressions)
            values = expressions[0].split(':')
            results = {
              :account => Settings.github.account,
              :repository => values[0],
              :branch => values[1]
            }

            expressions[1..-1].each do |expression|
              values = expression.split('=')
              results[values[0].gsub('-', '_').to_sym] = values[1]
            end

            results
          end
        end
      end

      class InvalidArgumentError < Error; end
    end
  end
end
