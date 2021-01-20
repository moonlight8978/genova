module Genova
  module Ecs
    class Client
      def initialize(cluster, code_manager, options = {})
        @cluster = cluster
        @code_manager = code_manager
        @logger = options[:logger] || ::Logger.new($stdout, level: Settings.logger.level)
        @task_definitions = {}

        @docker_client = Genova::Docker::Client.new(@code_manager, logger: @logger)
        @ecr_client = Genova::Ecr::Client.new(logger: @logger)
        @deploy_config = @code_manager.load_deploy_config
      end

      def ready
        @logger.info('Start sending images to ECR.')

        @ecr_client.authenticate
        @code_manager.update
      end

      def deploy_run_task(run_task, override_container, override_command, id)
        run_task_config = @deploy_config.run_task(@cluster, run_task)

        if override_container.present?
          run_task_config[:container_overrides] = [
            {
              name: override_container,
              command: override_command.split(' ')
            }
          ]
        end

        build(run_task_config[:containers], run_task_config[:path], id)

        task_definition_path = @code_manager.task_definition_config_path("config/#{run_task_config[:path]}")
        task_definition = create_task(task_definition_path, id)

        options = {
          desired_count: run_task_config[:desired_count],
          group: run_task_config[:group],
          container_overrides: run_task_config[:container_overrides],
          network_configuration: run_task_config[:network_configuration]
        }
        options[:launch_type] = run_task_config[:launch_type] if run_task_config[:launch_type].present?
        options[:task_role_arn] = Aws::IAM::Role.new(run_task_config[:task_role]).arn if run_task_config[:task_role]
        options[:task_execution_role_arn] = Aws::IAM::Role.new(run_task_config[:task_execution_role]).arn if run_task_config[:task_execution_role]

        run_task_client = Deployer::RunTask::Client.new(@cluster, @logger)
        run_task_client.execute(task_definition.task_definition_arn, options)
      end

      def deploy_service(service, id)
        service_config = @deploy_config.service(@cluster, service)
        cluster_config = @deploy_config.cluster(@cluster)

        build(service_config[:containers], service_config[:path], id)

        service_task_definition_path = @code_manager.task_definition_config_path("config/#{service_config[:path]}")
        service_task_definition = create_task(service_task_definition_path, id)

        service_client = Deployer::Service::Client.new(@cluster, @logger)

        raise Exceptions::ValidationError, "Service is not registered. [#{service}]" unless service_client.exist?(service)

        task_definition_arn = service_task_definition.task_definition_arn
        params = service_config.slice(
          :desired_count,
          :force_new_deployment,
          :health_check_grace_period_seconds,
          :minimum_healthy_percent,
          :maximum_percent
        )

        service_client.update(service, task_definition_arn, params)
        deploy_scheduled_tasks(id, depend_service: service) if cluster_config.include?(:scheduled_tasks)

        task_definition_arn
      end

      def deploy_scheduled_task(rule, target, id)
        deploy_scheduled_tasks(id, rule: rule, target: target)
      end

      private

      def build(containers_config, path, id)
        count = 0

        containers_config.each do |container_config|
          @ecr_client.push_image(id, @docker_client.build_image(container_config, path))
          count += 1
        end

        raise Exceptions::ValidationError, 'Push image is not found.' if count.zero?
      end

      def deploy_scheduled_tasks(id, params)
        task_definition_arns = []

        cluster_config = @deploy_config.cluster(@cluster)
        cluster_config[:scheduled_tasks].each do |scheduled_task_config|
          scheduled_task_client = Ecs::Deployer::ScheduledTask::Client.new(@cluster)
          config_base_path = Pathname(@code_manager.base_path).join('config').to_s
          targets = []

          next if params[:rule].present? && scheduled_task_config[:rule] != params[:rule]

          scheduled_task_config[:targets].each do |target_config|
            next if params[:depend_service].present? && target_config[:depend_service] != params[:depend_service]
            next if params[:target].present? && target_config[:name] != params[:target]

            build(target_config[:containers], target_config[:path], id) if params[:target].present?

            task_definition_path = File.expand_path(target_config[:path], config_base_path)
            task_definition = create_task(task_definition_path, id)

            task_definition_arn = task_definition.task_definition_arn

            values = {
              task_definition_arn: task_definition_arn,
              cloudwatch_event_iam_role_arn: Aws::IAM::Role.new(target_config[:cloudwatch_event_iam_role] || 'ecsEventsRole').arn,
              desired_count: target_config[:task_count] || target_config[:desired_count] || 1,
              container_overrides: target_config[:overrides] || target_config[:container_overrides]
            }
            values[:launch_type] = target_config[:launch_type] if target_config[:launch_type].present?
            values[:network_configuration] = target_config[:network_configuration] if target_config[:network_configuration].present?
            values[:task_role_arn] = Aws::IAM::Role.new(target_config[:task_role]).arn if target_config[:task_role].present?

            @logger.warn('"task_count" parameter is deprecated. Set variable "desired_count" instead.') if target_config[:task_count].present?
            @logger.warn('"overrides" parameter is deprecated. Set variable "container_overrides" instead.') if target_config[:overrides].present?

            targets << Ecs::Deployer::ScheduledTask::Target.build_hash(@cluster, target_config[:name], values)
            task_definition_arns << task_definition_arn
          end

          next if targets.size.zero?

          @logger.info("Update '#{scheduled_task_config[:rule]}' rule.")

          values = {
            enabled: scheduled_task_config[:enabled],
            description: scheduled_task_config[:description]
          }

          scheduled_task_client.update(
            scheduled_task_config[:rule],
            scheduled_task_config[:expression],
            targets,
            values
          )
        end

        raise Exceptions::ValidationError, 'Scheduled task target or rule is undefined.' if params[:rule].present? && task_definition_arns.count.zero?

        task_definition_arns
      end

      def create_task(task_definition_path, id)
        task_client = Ecs::Task::Client.new

        @task_definitions[task_definition_path] = task_client.register(task_definition_path, tag: id) unless @task_definitions.include?(task_definition_path)

        @task_definitions[task_definition_path]
      end
    end
  end
end
