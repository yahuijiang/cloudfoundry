module CloudController
  module Blobstore
    class Directory
      def initialize(connection, key)
        @connection = connection
        @key = key
      end
      #位connection创建一个directories
      def create
        @connection.directories.create(key: @key, public: false)
      end
      #获取connection的directory
      def get
        @connection.directories.get(@key, 'limit' => 1, max_keys: 1)
      end
    end
  end
end
