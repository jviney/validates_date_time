require File.dirname(__FILE__) + '/parser'

module ActiveRecord::Validations::DateTime
  def self.included(base)
    base.extend(ClassMethods)
    base.send(:include, InstanceMethods)
  end
  
  mattr_accessor :us_date_format
  us_date_format = false
  
  DEFAULT_TEMPORAL_VALIDATION_OPTIONS = {
    :before_message => "must be before %s",
    :after_message  => "must be after %s",
    :on => :save
  }.freeze
  
  class Restriction < Struct.new(:raw_value, :parse_method)
    def value(record)
      @last_value = case raw_value
        when Symbol
          record.send(raw_value)
        when Proc
          raw_value.call(record)
        else
          raw_value
      end
      
      @last_value = parse(@last_value)
    end
    
    def parse(string)
      ActiveRecord::ConnectionAdapters::Column.send("string_to_#{parse_method}", string)
    end
    
    def last_value
      @last_value
    end
    
    def to_s
      if raw_value.is_a?(Symbol)
        raw_value.to_s.humanize
      else
        @last_value.to_s
      end
    end
  end
  
  
  module ClassMethods
    def validates_date(*args)
      options = temporal_validation_options({ :message => "is an invalid date" }, args)
      attr_names = args
      
      # We must remove this from the configuration that is passed to validates_each because
      # we want to have our own definition of nil that uses the before_type_cast value
      allow_nil = options.delete(:allow_nil)
      
      prepare_restrictions(options, :date)
      
      validates_each(attr_names, options) do |record, attr_name, value|
        raw_value = record.send("#{attr_name}_before_type_cast")
        
        # If value that is unable to be parsed, and a blank value where allow_nil is not set are both invalid
        if (!raw_value.blank? and !value) || (raw_value.blank? and !allow_nil)
          record.errors.add(attr_name, options[:message])
        elsif value
          validate_before_and_after_restrictions(record, attr_name, value, options)
        end
      end
    end
    
    def validates_time(*args)
      options = temporal_validation_options({ :message => "is an invalid time" }, args)
      attr_names = args
      
      allow_nil = options.delete(:allow_nil)
      prepare_restrictions(options, :dummy_time)
      
      validates_each(attr_names, options) do |record, attr_name, value|
        raw_value = record.send("#{attr_name}_before_type_cast")
        
        if (!raw_value.blank? and !value) || (raw_value.blank? and !allow_nil)
          record.errors.add(attr_name, options[:message])
        elsif value
          validate_before_and_after_restrictions(record, attr_name, value, options)
        end
      end
    end
    
    def validates_date_time(*args)
      options = temporal_validation_options({ :message => "is an invalid date time" }, args)
      attr_names = args
      
      allow_nil = options.delete(:allow_nil)
      prepare_restrictions(options, :time)
      
      validates_each(attr_names, options) do |record, attr_name, value|
        raw_value = record.send("#{attr_name}_before_type_cast")
        
        if (!raw_value.blank? and !value) || (raw_value.blank? and !allow_nil)
          record.errors.add(attr_name, options[:message])
        elsif value
          validate_before_and_after_restrictions(record, attr_name, value, options)
        end
      end
    end
    
   private
    def validate_before_and_after_restrictions(record, attr_name, value, options)
      if options[:before]
        options[:before].each do |r|
          if r.value(record) and value >= r.last_value
            record.errors.add(attr_name, options[:before_message] % r)
            break
          end
        end
      end
      
      if options[:after]
        options[:after].each do |r|
          if r.value(record) and value < r.last_value
            record.errors.add(attr_name, options[:after_message] % r)
            break
          end
        end
      end
    end
    
    def prepare_restrictions(options, parse_method)
      options[:before] = [*options[:before]].compact.map { |r| Restriction.new(r, parse_method) }
      options[:after] = [*options[:after]].compact.map { |r| Restriction.new(r, parse_method) }
    end
    
    def temporal_validation_options(options, args)
      options.reverse_merge!(DEFAULT_TEMPORAL_VALIDATION_OPTIONS)
      options.update(args.pop) if args.last.is_a?(Hash)
      options.assert_valid_keys :message, :before_message, :after_message, :before, :after, :if, :on, :allow_nil
      options
    end
  end
  
  module InstanceMethods
    def execute_callstack_for_multiparameter_attributes_with_temporal_error_handling(callstack)
      errors = []
      callstack.each do |name, values|
        klass = (self.class.reflect_on_aggregation(name.to_sym) || column_for_attribute(name)).klass
        
        if values.empty?
          send("#{name}=", nil)
        else
          column = column_for_attribute(name)
          
          if [:date, :time, :datetime].include?(column.type)
            values = values.map(&:to_s)
            
            string = case column.type
              when :date
                extract_date_from_multiparameter_attributes(values)
              when :time
                extract_time_from_multiparameter_attributes(values)
              when :datetime
                extract_date_from_multiparameter_attributes(values) + " " + extract_time_from_multiparameter_attributes(values)
            end
                   
            send("#{name}=", string)
          end
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

class ActiveRecord::Base
  include ActiveRecord::Validations::DateTime
  
  alias_method_chain :execute_callstack_for_multiparameter_attributes, :temporal_error_handling
end
