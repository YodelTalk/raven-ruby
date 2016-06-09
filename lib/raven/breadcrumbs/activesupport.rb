module Raven
  module ActiveSupportBreadcrumbs
    class << self
        def add(name, started, _finished, _unique_id, data)
          message = case name
                      when 'sql.active_record' then data.sql
                      when 'write_fragment.action_controller' then data.key
                      else name
                    end

          if name == 'deliver.action_mailer' || name == 'receive.action_mailer'
            data = data.clone
            data.delete('mail')
          end

          Raven.breadcrumbs.record do |crumb|
            crumb.message = message
            crumb.data = data
            crumb.category = "active_support.#{name}"
            crumb.timestamp = started.to_i
          end
        end

        def inject
          ActiveSupport::Notifications.subscribe(/.*/) do |name, started, finished, unique_id, data|
            begin
              add(name, started, finished, unique_id, data)
            rescue StandardError => exception
              Raven.logger.error "Unable to record breadcrumb for #{name}: #{exception}"
            end
          end
        end
    end
  end
end
