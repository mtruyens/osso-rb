# frozen_string_literal: true

module Osso
  module GraphQL
    module Mutations
      class UpdateAppConfig < BaseMutation
        null false

        argument :name, String, required: false
        argument :logo_url, String, required: false
        argument :contact_email, String, required: false

        field :app_config, Types::AppConfig, null: true
        field :errors, [String], null: false

        def resolve(**args)
          app_config = Osso::Models::AppConfig.find
          if app_config.update(**args)
            Osso::Analytics.capture(email: context[:email], event: self.class.name.demodulize, properties: args)
            return response_data(app_config: app_config)
          end

          response_error(app_config.errors)
        end

        def ready?(*)
          admin_ready?
        end
      end
    end
  end
end
