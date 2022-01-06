module Git
  class Lib
    def branches_all
      arr = []
      count = 0

      command_lines('branch', ['-a', '--sort=-authordate']).each do |b|
        current = (b[0, 2] == '* ')
        arr << [b.gsub('* ', '').strip, current]
        count += 1

        break if count == Settings.slack.interactive.branch_limit
      end
      arr
    end

    def tags
      arr = []
      count = 0

      command_lines('tag', ['--sort=-v:refname']).each do |t|
        arr << t
        count += 1

        break if count == Settings.slack.interactive.tag_limit
      end
      arr
    end

    def update_submodules
      command("submodule update")
    end
  end

  class Base
    def update_submodules
      lib.update_submodules
    end
  end
end

module Genova
  module CodeManager
    class Git
      attr_reader :repos_path, :base_path

      def initialize(repository, options = {})
        @account = Settings.github.account
        @branch = options[:branch]
        @tag = options[:tag]
        @logger = options[:logger] || ::Logger.new($stdout, level: Settings.logger.level)
        @repository = repository
        @repos_path = Rails.root.join('tmp', 'repos', @account, @repository).to_s

        name_or_alias = options[:alias].present? ? options[:alias] : @repository
        @repository_config = Genova::Config::SettingsHelper.find_repository(name_or_alias)

        @base_path = @repository_config.nil? || @repository_config[:base_path].nil? ? @repos_path : Pathname(@repos_path).join(@repository_config[:base_path]).to_s

        ::Git.configure do |config|
          path = Rails.root.join('.ssh/id_rsa').to_s
          raise IOError, "File does not exist. [#{path}]" unless File.file?(path)

          config.git_ssh = Rails.root.join('.ssh/git-ssh.sh').to_s
        end
      end

      def update
        FileUtils.rm_rf(@repos_path)

        git = client

        @logger.info("Git checkout: #{@branch}")

        if @branch.present?
          checkout = @branch
          reset_hard = "origin/#{@branch}"
        else
          checkout = "refs/tags/#{@tag}"
          reset_hard = "refs/tags/#{@tag}"
        end

        git.fetch
        git.clean(ff: true, d: true, force: true)
        git.checkout(checkout)
        git.reset_hard(reset_hard)
        git.update_submodules

        git.log(1).to_s
      end

      def load_deploy_config
        Genova::Config::DeployConfig.new(fetch_config('config/deploy.yml'))
      end

      def task_definition_config_path(path)
        File.expand_path(Pathname(@base_path).join(path).to_s)
      end

      def load_task_definition_config(path)
        Genova::Config::TaskDefinitionConfig.new(fetch_config(path))
      end

      def origin_branches
        git = client
        git.fetch

        branches = []

        git.branches.remote.each do |branch|
          next if branch.name.include?('->')

          branches << branch.name
        end

        branches
      end

      def origin_tags
        git = client
        git.fetch

        tags = []

        git.tags.each do |tag|
          tags << tag.name
        end

        tags
      end

      def origin_last_commit
        git = client
        git.fetch

        if @branch.present?
          git.remote.branch(@branch).gcommit.log(1).first.to_s
        else
          puts git.tag(@tag).sha
        end
      end

      def find_commit(tag)
        git = client
        git.fetch
        git.tag(tag).sha
      rescue ::Git::GitTagNameDoesNotExist
        nil
      end

      def release(tag, commit)
        update

        git = client
        git.add_tag(tag, commit)
        git.push('origin', @branch, tags: tag)
      end

      private

      def fetch_config(path)
        path = Pathname(@repository_config[:base_path]).join(path).cleanpath.to_s if @repository_config.present? && @repository_config[:base_path].present?

        client.fetch

        config = if @branch.present?
                   client.show("origin/#{@branch}", path)
                 else
                   client.show("tags/#{@tag}", path)
                 end

        YAML.load(config).deep_symbolize_keys
      end

      def clone
        return if File.file?("#{@repos_path}/.git/config")

        FileUtils.rm_rf(@repos_path)
        uri = Genova::Github::Client.new(@repository).build_clone_uri
        @logger.info("Git clone: #{uri}")

        ::Git.clone(uri, '', path: @repos_path, recursive: true, branch: @branch)
      end

      def client
        clone
        ::Git.open(@repos_path, log: @logger)
      end
    end
  end
end
