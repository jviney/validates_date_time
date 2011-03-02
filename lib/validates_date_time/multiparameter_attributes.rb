require "active_record/errors"

module ValidatesDateTime
  module MultiparameterAttributes
    extend ActiveSupport::Concern
    
    included do
      alias_method_chain :execute_callstack_for_multiparameter_attributes, :temporal_error_handling
    end
    
    module InstanceMethods
      def execute_callstack_for_multiparameter_attributes_with_temporal_error_handling(callstack)
        errors = []
        callstack.each do |name, values_with_empty_parameters|
          begin
            klass = (self.class.reflect_on_aggregation(name.to_sym) || column_for_attribute(name)).klass
            # in order to allow a date to be set without a year, we must keep the empty values.
            # Otherwise, we wouldn't be able to distinguish it from a date with an empty day.
            values = values_with_empty_parameters.reject { |v| v.nil? }

            if values.empty?
              send(name + "=", nil)
            else
              # Alter handling of date, time, and datetime columns
              column = column_for_attribute(name)
              
              value = if [:date, :time, :datetime].include?(column.type)
                values = values.map(&:to_s)
              
                case column.type
                when :date
                  extract_date_from_multiparameter_attributes(values)
                when :time
                  extract_time_from_multiparameter_attributes(values)
                when :datetime
                  date_values, time_values = values.slice!(0, 3), values
                  extract_date_from_multiparameter_attributes(date_values) + " " + extract_time_from_multiparameter_attributes(time_values)
                end
              else
                klass.new(*values)
              end

              send(name + "=", value)
            end
          rescue => ex
            errors << ActiveRecord::AttributeAssignmentError.new("error on assignment #{values.inspect} to #{name}", ex, name)
          end
        end
        unless errors.empty?
          raise ActiveRecord::MultiparameterAssignmentErrors.new(errors), "#{errors.size} error(s) on assignment of multiparameter attributes"
        end
      end
    
      def extract_date_from_multiparameter_attributes(values)
        [values[0], *values.slice(1, 2).map { |s| s.rjust(2, "0") }].join("-")
      end
    
      def extract_time_from_multiparameter_attributes(values)
        values.last(3).map { |s| s.rjust(2, "0") }.join(":")
      end
    end
  end
end

