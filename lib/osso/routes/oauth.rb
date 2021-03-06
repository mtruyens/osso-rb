# frozen_string_literal: true

require 'rack/oauth2'

module Osso
  class Oauth < Sinatra::Base
    include AppConfig
    register Sinatra::Namespace

    namespace '/oauth' do # rubocop:disable Metrics/BlockLength
      # Send your users here in order to being an authentication
      # flow. This flow follows the authorization grant oauth
      # spec with one exception - you must also pass the domain
      # of the user who wants to sign in. If the sign in request
      # is valid, the user is redirected to their Identity Provider.
      # Once they complete IdP login, they will be returned to the
      # redirect_uri with an authorization code parameter.
      get '/authorize' do
        validate_oauth_request(env)

        return erb :hosted_login if render_hosted_login?

        @providers = find_providers

        return erb :saml_login_form if @providers.one?

        return erb :multiple_providers if @providers.count > 1

        raise Osso::Error::MissingConfiguredIdentityProvider.new(domain: params[:domain])
      rescue Osso::Error::Base => e
        @error = e
        erb :error
      end

      # Exchange an authorization code for an access token.
      # In addition to the authorization code, you must include all
      # paramaters required by OAuth spec: redirect_uri, client ID,
      # and client secret
      post '/token' do
        Rack::OAuth2::Server::Token.new do |req, res|
          client = Models::OauthClient.find_by!(identifier: req.client_id)
          req.invalid_client! if client.secret != req.client_secret

          code = Models::AuthorizationCode.find_by_token!(params[:code])
          req.invalid_grant! if code.redirect_uri != req.redirect_uri

          res.access_token = code.access_token.to_bearer_token
        end.call(env)
      end

      # Use the access token to request a profile for the user who
      # just logged in. Access tokens are short-lived.
      get '/me' do
        token = Models::AccessToken.
          includes(:user).
          valid.
          find_by_token!(access_token)

        json token.user.as_json.merge(requested: token.requested)
      end
    end

    private

    def render_hosted_login?
      [params[:email], params[:domain]].all?(&:nil?)
    end

    def find_providers
      if params[:email]
        user = Osso::Models::User.
          includes(:identity_provider).
          find_by(email: params[:email])
        return [user.identity_provider] if user
      end

      Osso::Models::IdentityProvider.
        joins(:oauth_client).
        not_pending.
        where(
          domain: domain_from_params,
          oauth_clients: { identifier: params[:client_id] },
        )
    end

    def domain_from_params
      params[:domain] || params[:email].split('@')[1]
    end

    def find_client(identifier)
      @client ||= Models::OauthClient.find_by!(identifier: identifier)
    rescue ActiveRecord::RecordNotFound
      raise Osso::Error::InvalidOAuthClientIdentifier
    end

    def validate_oauth_request(env) # rubocop:disable Metrics/AbcSize
      Rack::OAuth2::Server::Authorize.new do |req, _res|
        client = find_client(req[:client_id])
        session[:osso_oauth_redirect_uri] = req.verify_redirect_uri!(client.redirect_uri_values)
        session[:osso_oauth_state] = params[:state]
        session[:osso_oauth_requested] = { domain: req[:domain], email: req[:email] }
      end.call(env)
    rescue Rack::OAuth2::Server::Authorize::BadRequest
      raise Osso::Error::InvalidRedirectUri.new(redirect_uri: params[:redirect_uri])
    end

    def access_token
      params[:access_token] || env.fetch('HTTP_AUTHORIZATION', '').slice(-64..-1)
    end
  end
end
