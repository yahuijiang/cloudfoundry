module VCAP::CloudController
  module Dea
    class Stager
      def initialize(app, config, message_bus, dea_pool, stager_pool, runners)
        @app         = app
        @config      = config
        @message_bus = message_bus
        @dea_pool    = dea_pool
        @stager_pool = stager_pool
        @runners     = runners
      end
      #从stager pool中选择出一个stager，然后根据stager的id 来减小dea poo，stager pool中相应的dea和stager 的advertisement 的可用内存
      #最后返回stager结果
      def stage_package(droplet, stack, memory_limit, disk_limit, buildpack_key, buildpack_git_url)
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator

       # PackageStagerTask参数
       # config                  = config
       # message_bus             = message_bus
       # dea_pool                = dea_pool
       # stager_pool             = stager_pool
        task = PackageStagerTask.new(@config, @message_bus, @dea_pool, @stager_pool)

        staging_message = PackageDEAStagingMessage.new(
          @app, droplet.guid, droplet.guid, stack, memory_limit, disk_limit, buildpack_key,
          buildpack_git_url, @config, droplet.environment_variables, blobstore_url_generator)
        #从stager pool中选择出一个stager，然后根据stager的id 来减小dea poo，stager pool中相应的dea和stager 的advertisement 的可用内存
        task.stage(staging_message) do |staging_result, error|
          if error
            add_error_to_droplet(droplet, error)
          else
            buildpack = Buildpack.find(key: staging_result.buildpack_key)
            droplet.db.transaction do
              droplet.lock!
              droplet.state                  = DropletModel::STAGED_STATE
              droplet.buildpack_guid         = buildpack.guid if buildpack
              droplet.detected_start_command = staging_result.detected_start_command
              droplet.procfile               = YAML.dump(staging_result.procfile, line_width: -1)
              droplet.save
            end
          end
        end
      rescue PackageStagerTask::FailedToStage => e
        add_error_to_droplet(droplet, e)
        raise VCAP::Errors::ApiError.new_from_details('StagingError', e.message)
      end

      def stage_app
        blobstore_url_generator = CloudController::DependencyLocator.instance.blobstore_url_generator
        task = AppStagerTask.new(@config, @message_bus, @app, @dea_pool, @stager_pool, blobstore_url_generator)

        @app.last_stager_response = task.stage do |staging_result|
          @runners.runner_for_app(@app).start(staging_result)
        end
      end

      def staging_complete(_, _)
        raise NotImplementedError
      end

      def add_error_to_droplet(droplet, error)
        droplet.db.transaction do
          droplet.lock!
          droplet.state          = DropletModel::FAILED_STATE
          droplet.error = "#{error.type}: #{error.message}"
          droplet.save
        end
      end
    end
  end
end
