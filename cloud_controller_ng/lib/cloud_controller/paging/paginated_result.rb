module VCAP::CloudController
  class PaginatedResult
    attr_reader :records, :total, :pagination_options
#app���м�¼��ҳ��Ķ���
    def initialize(records, total, pagination_options)
      @records            = records
      @total              = total
      @pagination_options = pagination_options
    end
  end
end
