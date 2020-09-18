# frozen_string_literal: true

require 'cgi'
require 'omniauth'
require 'omniauth-multi-provider'
require 'omniauth-saml'

module Osso
  class Auth < Sinatra::Base
    include AppConfig
    register Sinatra::Namespace

    UUID_REGEXP =
      /[0-9a-f]{8}-[0-9a-f]{3,4}-[0-9a-f]{4}-[0-9a-f]{3,4}-[0-9a-f]{12}/.
        freeze

    use OmniAuth::Builder do
      OmniAuth::MultiProvider.register(
        self,
        provider_name: 'saml',
        identity_provider_id_regex: UUID_REGEXP,
        path_prefix: '/auth/saml',
        callback_suffix: 'callback',
      ) do |identity_provider_id, _env|
        Models::IdentityProvider.find(identity_provider_id).
          saml_options
      end
    end

    namespace '/auth' do # rubocop:disable Metrics/BlockLength
      get '/failure' do
        @error = params[:message]
        erb :error
      end

      # Enterprise users are sent here after authenticating against
      # their Identity Provider. We find or create a user record,
      # and then create an authorization code for that user. The user
      # is redirected back to your application with this code
      # as a URL query param, which you then exchange for an access token.
      post '/saml/:provider_id/callback' do
        redirect_uri = UserBuilder.perform(
          auth_hash: env['omniauth.auth'],
          provider_id: params[:provider_id],
          session: session,
        )
        
        redirect(redirect_uri)
      end
    end
  end
end
