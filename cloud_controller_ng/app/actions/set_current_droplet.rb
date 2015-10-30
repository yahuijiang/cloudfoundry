require 'cloud_controller/procfile'

module VCAP::CloudController
  class SetCurrentDroplet
    class InvalidApp < StandardError; end

    def initialize(user, user_email)
      @user = user
      @user_email = user_email
      @logger = Steno.logger('cc.action.procfile_parse')
    end

    def update_to(app, droplet)
      app.db.transaction do
        app.lock!
        update_app(app, { droplet_guid: droplet.guid })#更新app的droplet_id
        procfile_parse.process_procfile(app)#将app的进程进行更新，并且销毁app中与新的profile不匹配的进程
        app.save
      end

      app
    rescue Sequel::ValidationFailed => e
      raise InvalidApp.new(e.message)
    end

    private

    def procfile_parse
      ProcfileParse.new(@user.guid, @user_email)
    end

    def update_app(app, fields)
      app.update(fields)#更新app相应的阈
      Repositories::Runtime::AppEventRepository.new.record_app_set_current_droplet(
          app,
          app.space,
          @user.guid,
          @user_email,
          fields
      )
    end
  end
end
