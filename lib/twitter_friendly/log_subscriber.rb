module TwitterFriendly
  module Logging
    def truncated_payload(payload)
      return payload.inspect if !payload.has_key?(:args) || !payload[:args].is_a?(Array) || payload[:args].empty? || !payload[:args][0].is_a?(Array)

      args = payload[:args].dup
      args[0] =
        if args[0].size > 3
          "[#{args[0].take(3).join(', ')} ... #{args[0].size}]"
        else
          args[0].inspect
        end

      {args: args}.merge(payload.except(:args)).inspect
    end

    def indentation(payload)
      (payload[:super_operation] ? '  ' : '') + (payload[:super_super_operation] ? '  ' : '') + (payload[:name] == 'write' ? '  ' : '')
    end

    module_function

    def logger
      @@logger
    end

    def logger=(logger)
      @@logger = logger
    end
  end

  class TFLogSubscriber < ::ActiveSupport::LogSubscriber
    include Logging

    def start_processing(event)
      debug do
        payload = event.payload
        name = "#{indentation(payload)}TF::Started #{payload.delete(:operation)}"

        if payload[:super_operation]
          "#{name} in #{payload[:super_operation]} at #{Time.now}"
        else
          "#{name} at #{Time.now}"
        end
      end
    end

    def complete_processing(event)
      debug do
        payload = event.payload
        name = "TF::Completed #{payload.delete(:operation)} in #{event.duration.round(1)}ms"

        "#{indentation(payload)}#{name}#{" #{truncated_payload(payload)}" unless payload.empty?}"
      end
    end

    def collect(event)
      debug do
        payload = event.payload
        payload.delete(:name)
        operation = payload.delete(:operation)
        name = "  TW::#{operation.capitalize} #{payload[:args].last[:super_operation]} in #{payload[:args][0]} (#{event.duration.round(1)}ms)"
        name = color(name, BLUE, true)
        "  #{indentation(payload)}#{name}#{" #{payload[:args][1]}" unless payload.empty?}"
      end
    end

    def twitter_friendly_any(event)
      debug do
        payload = event.payload
        payload.delete(:name)
        operation = payload.delete(:operation)
        name = "  TW::#{operation.capitalize} #{payload[:args][0]} (#{event.duration.round(1)}ms)"
        c = (%i(encode decode).include?(operation.to_sym)) ? YELLOW : CYAN
        name = color(name, c, true)
        "  #{indentation(payload)}#{name}#{" #{payload[:args][1]}" unless payload.empty?}"
      end
    end

    %w(request encode decode).each do |operation|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{operation}(event)
          event.payload[:name] = '#{operation}'
          twitter_friendly_any(event)
        end
      METHOD
    end
  end

  class ASLogSubscriber < ::ActiveSupport::LogSubscriber
    include Logging

    def cache_any(event)
      debug do
        payload = event.payload
        operation = payload[:super_operation] == :fetch ? :fetch : payload[:name]
        hit = %i(read fetch).include?(operation.to_sym) && payload[:hit] ? ' (Hit)' : ''
        name = "  AS::#{operation.capitalize}#{hit} #{payload[:key].split(':')[1]} (#{event.duration.round(1)}ms)"
        name = color(name, MAGENTA, true)
        "#{indentation(payload)}#{name} #{(payload.except(:name, :expires_in, :super_operation, :hit, :race_condition_ttl, :tf_super_operation).inspect)}"
      end
    end

    # Ignore generate and fetch_hit
    %w(read write delete exist?).each do |operation|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def cache_#{operation}(event)
          event.payload[:name] = '#{operation}'
          cache_any(event)
        end
      METHOD
    end
  end
end