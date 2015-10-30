module VCAP::CloudController
  module Dea
    module SubSystem
      def self.setup!(message_bus)
        Client.run
      #注册订阅
        LegacyBulk.register_subscription

        hm9000_respondent = HM9000::Respondent.new(Client, message_bus)
        hm9000_respondent.handle_requests#监听start和stop instance的请求，并且处理请求（判断是否能执行请求）

        dea_respondent = Respondent.new(message_bus)
        dea_respondent.start#监听处理droplet的exit message
      end
    end
  end
end
