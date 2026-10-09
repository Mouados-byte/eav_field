# frozen_string_literal: true

module EavField
  class Error < StandardError; end
  class UnknownField < Error; end
  class InvalidValue < Error; end
  class UnsupportedQuery < Error; end
  class NotEnabled < Error; end
end
