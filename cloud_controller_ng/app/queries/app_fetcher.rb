module VCAP::CloudController
  class AppFetcher
    #通过app_id获取查询app表获取相应的数据库记录
    def fetch(app_guid)
      app = AppModel.where(guid: app_guid).eager(:processes, :space, space: :organization).all.first
      return nil if app.nil?

      org = app.space ? app.space.organization : nil
      [app, app.space, org]
    end
  end
end
