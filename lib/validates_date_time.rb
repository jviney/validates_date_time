require "active_support/concern"
require "active_support/core_ext/module/attribute_accessors"
require "active_support/core_ext/class/attribute"

require "validates_date_time/parser"
require "validates_date_time/temporal_validator"
require "validates_date_time/multiparameter_attributes"

require "active_record"

module ValidatesDateTime
  extend ActiveSupport::Concern

  included do
    include MultiparameterAttributes
  end

  mattr_accessor :us_date_format
  self.us_date_format = false

  module ClassMethods
    def validates_date(*attr_names)
      validates_with TemporalValidator, _merge_attributes(attr_names).update(:_parse_method => :date, :message => "is an invalid date")
    end

    def validates_time(*attr_names)
      validates_with TemporalValidator, _merge_attributes(attr_names).update(:_parse_method => :dummy_time, :message => "is an invalid time")
    end

    def validates_date_time(*attr_names)
      validates_with TemporalValidator, _merge_attributes(attr_names).update(:_parse_method => :time, :message => "is an invalid date time")
    end
  end
end

class ActiveRecord::Base
  include ValidatesDateTime
end
