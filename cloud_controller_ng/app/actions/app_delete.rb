module VCAP::CloudController
  class AppDelete
    attr_reader :user_guid, :user_email
    #app delete object,此操作的操作者user_id，user_email
    def initialize(user_guid, user_email)
      @user_guid = user_guid
      @user_email = user_email
      @logger = Steno.logger('cc.action.app_delete')
    end
    #delete 相应的app
    def delete(apps)
      apps = [apps] unless apps.is_a?(Array)

      apps.each do |app|
        PackageDelete.new.delete(packages_to_delete(app))#在blobstore中删除相应的package
        DropletDelete.new.delete(droplets_to_delete(app))#在blobstore中删除相应的droplet
        ProcessDelete.new.delete(processes_to_delete(app))#销毁相应的进程
        app.remove_all_routes
      #添加本操作的记录
        Repositories::Runtime::AppEventRepository.new.record_app_delete_request(
          app,
          app.space,
          @user_guid,
          @user_email
        )

        app.destroy#销毁app表中的数据
      end
    end

    private
    #选择app_model的所有符合要求的package dataset 来delete
    def packages_to_delete(app_model)
      app_model.packages_dataset.select(:"#{PackageModel.table_name}__guid", :"#{PackageModel.table_name}__id").all
    end
    #选择app_model中所有符合要求的dataset 进行删除
    def droplets_to_delete(app_model)
      app_model.droplets_dataset.
        select(:"#{DropletModel.table_name}__guid",
        :"#{DropletModel.table_name}__id",
        :"#{DropletModel.table_name}__droplet_hash").all
    end
    #删除相应的进程
    def processes_to_delete(app_model)
      app_model.processes_dataset.
        select(:"#{App.table_name}__guid",
        :"#{App.table_name}__id",
        :"#{App.table_name}__app_guid",
        :"#{App.table_name}__name").all
    end
  end
end
