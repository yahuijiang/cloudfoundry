module VCAP::CloudController
  class AppDelete
    attr_reader :user_guid, :user_email
    #app delete object,�˲����Ĳ�����user_id��user_email
    def initialize(user_guid, user_email)
      @user_guid = user_guid
      @user_email = user_email
      @logger = Steno.logger('cc.action.app_delete')
    end
    #delete ��Ӧ��app
    def delete(apps)
      apps = [apps] unless apps.is_a?(Array)

      apps.each do |app|
        PackageDelete.new.delete(packages_to_delete(app))#��blobstore��ɾ����Ӧ��package
        DropletDelete.new.delete(droplets_to_delete(app))#��blobstore��ɾ����Ӧ��droplet
        ProcessDelete.new.delete(processes_to_delete(app))#������Ӧ�Ľ���
        app.remove_all_routes
      #��ӱ������ļ�¼
        Repositories::Runtime::AppEventRepository.new.record_app_delete_request(
          app,
          app.space,
          @user_guid,
          @user_email
        )

        app.destroy#����app���е�����
      end
    end

    private
    #ѡ��app_model�����з���Ҫ���package dataset ��delete
    def packages_to_delete(app_model)
      app_model.packages_dataset.select(:"#{PackageModel.table_name}__guid", :"#{PackageModel.table_name}__id").all
    end
    #ѡ��app_model�����з���Ҫ���dataset ����ɾ��
    def droplets_to_delete(app_model)
      app_model.droplets_dataset.
        select(:"#{DropletModel.table_name}__guid",
        :"#{DropletModel.table_name}__id",
        :"#{DropletModel.table_name}__droplet_hash").all
    end
    #ɾ����Ӧ�Ľ���
    def processes_to_delete(app_model)
      app_model.processes_dataset.
        select(:"#{App.table_name}__guid",
        :"#{App.table_name}__id",
        :"#{App.table_name}__app_guid",
        :"#{App.table_name}__name").all
    end
  end
end
