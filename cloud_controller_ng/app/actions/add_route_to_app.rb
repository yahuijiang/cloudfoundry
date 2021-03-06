module VCAP::CloudController
  class AddRouteToApp
    class InvalidRouteMapping < StandardError; end

    def initialize(user, user_email)
      @user       = user
      @user_email = user_email
    end
    #如果存在process，则丢process添加route
    #更新dea的 uri
    def add(app, route, process)
      AppModelRoute.create(app: app, route: route, type: 'web')

      if !process.nil?
        process.add_route(route)#添加router

        if process.dea_update_pending?
          Dea::Client.update_uris(process)#发送dea 的update 消息,message 内容为：droplet 和 uris
        end
      end

      Repositories::Runtime::AppEventRepository.new.record_map_route(app, route, @user.try(:guid), @user_email)

    rescue Sequel::ValidationFailed => e
      if e.errors && e.errors.on([:app_v3_id, :route_id]).include?(:unique)
        # silently swallow, this means the mapping exists so the user got what they asked for
        return
      end

      raise InvalidRouteMapping.new(e.message)
    end
  end
end
