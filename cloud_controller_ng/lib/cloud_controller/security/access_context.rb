module VCAP::CloudController
  module Security
    class AccessContext
      include ::Allowy::Context

      def roles
        VCAP::CloudController::SecurityContext.roles
      end

      def user_email
        VCAP::CloudController::SecurityContext.current_user_email
      end

      def user
        VCAP::CloudController::SecurityContext.current_user
      end
    end
  end
end
