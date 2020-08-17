# frozen_string_literal: true

require 'rack/oauth2'

module Osso
  class Oauth < Sinatra::Base
    include AppConfig
    register Sinatra::Namespace

    namespace '/oauth' do
      # Send your users here in order to being an authentication
      # flow. This flow follows the authorization grant oauth
      # spec with one exception - you must also pass the domain
      # of the user who wants to sign in.
      get '/authorize' do
        @enterprise = Models::EnterpriseAccount.
          includes(:identity_providers).
          find_by!(domain: params[:domain])

        Rack::OAuth2::Server::Authorize.new do |req, _res|
          client = Models::OauthClient.find_by!(identifier: req.client_id)
          req.verify_redirect_uri!(client.redirect_uri_values)
        end.call(env)

        if @enterprise.single_provider?
          session[:osso_oauth_state] = params[:state]
          redirect "/auth/saml/#{@enterprise.provider.id}"
        end

        # TODO: multiple provider support
        # erb :multiple_providers

      rescue Rack::OAuth2::Server::Authorize::BadRequest => e
        @error = e
        return erb :error
      end

      # Exchange an authorization code token for an access token.
      # In addition to the token, you must include all paramaters
      # required by OAuth spec: redirect_uri, client ID, and client secret
      post '/token' do
        Rack::OAuth2::Server::Token.new do |req, res|
          code = Models::AuthorizationCode.
            find_by_token!(params[:code])
          client = Models::OauthClient.find_by!(identifier: req.client_id)
          req.invalid_client! if client.secret != req.client_secret
          req.invalid_grant! if code.redirect_uri != req.redirect_uri
          res.access_token = code.access_token.to_bearer_token
        end.call(env)
      end

      # Use the access token to request a user profile
      get '/me' do
        json Models::AccessToken.
          includes(:user).
          valid.
          find_by_token!(params[:access_token]).
          user
      end
    end
  end
end
