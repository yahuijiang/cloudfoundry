require 'cloud_controller/procfile'

module VCAP::CloudController
  class ProcfileParse
    class DropletNotFound < StandardError; end
    class ProcfileNotFound < StandardError; end

    def initialize(user_guid, user_email)
      @user_guid = user_guid
      @user_email = user_email
      @logger = Steno.logger('cc.action.procfile_parse')
    end

    def process_procfile(app)
      @logger.info('proccess_procfile', guid: app.guid)

      if app.droplet && app.droplet.procfile
        @logger.debug('using the droplet procfile', guid: app.guid)

        procfile = Procfile.load(app.droplet.procfile)#从droplet的读取profile文件，return a hash object
        converge_on_procfile(app, procfile)#将app的进程进行更新，并且销毁app中与新的profile不匹配的进程
        procfile
      else
        @logger.warn('no procfile found', guid: app.guid)
        raise ProcfileNotFound
      end
    end

    private

    attr_reader :user_guid, :user_email

    def converge_on_procfile(app, procfile_hash)
      types = []
      procfile_hash.each do |(type, command)|
        type = type.to_s
        types << type
        process_procfile_line(app, type, command)#根据procfile 来更新进程
      end
      processes = app.processes_dataset.where(Sequel.~(type: types))#找到app中和types不匹配的进程进行销毁
      ProcessDelete.new.delete(processes.all)
    end

    def process_procfile_line(app, type, command)
      existing_process = app.processes_dataset.where(type: type).first
      if existing_process
        message = { command: command }
        existing_process.update(message)#更新数据库中的进程
        process_event_repository.record_app_update(existing_process, app.space, user_guid, user_email, message)
      else
        message = {
          command: command,
          type: type,
          space: app.space,
          name: "v3-#{app.name}-#{type}",
          metadata: {},
          instances: type == 'web' ? 1 : 0
        }
        app.add_process(message)#新建一个进程
      end
    end

    def process_event_repository
      Repositories::Runtime::AppEventRepository.new
    end
  end
end
