module VCAP::CloudController
  module Dea
    module SubSystem
      def self.setup!(message_bus)
        Client.run
      #ע�ᶩ��
        LegacyBulk.register_subscription

        hm9000_respondent = HM9000::Respondent.new(Client, message_bus)
        hm9000_respondent.handle_requests#����start��stop instance�����󣬲��Ҵ��������ж��Ƿ���ִ������

        dea_respondent = Respondent.new(message_bus)
        dea_respondent.start#��������droplet��exit message
      end
    end
  end
end
