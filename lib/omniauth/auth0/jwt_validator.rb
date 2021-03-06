require 'base64'
require 'uri'
require 'json'
require 'omniauth'

module OmniAuth
  module Auth0
    class JWTValidator

      attr_accessor :issuer

      # Initializer
      # @param options object
      #   options.domain - Application domain.
      #   options.client_id - Application Client ID.
      #   options.client_secret - Application Client Secret.
      def initialize(options)
        temp_domain = URI(options.domain)
        temp_domain = URI("https://#{options.domain}") unless temp_domain.scheme
        @issuer = "#{temp_domain.to_s}/"

        @client_id = options.client_id
        @client_secret = options.client_secret
      end

      # Decode a JWT.
      # @param jwt string - JWT to decode.
      # @return hash - The decoded token, if there were no exceptions.
      # @see https://github.com/jwt/ruby-jwt
      def decode(jwt)
        head = token_head(jwt)

        # Make sure the algorithm is supported and get the decode key.
        if head[:alg] == 'RS256'
          jwks_x5c = jwks_key(:x5c, head[:kid])
          raise JWT::VerificationError, :jwks_missing_x5c if jwks_x5c.nil?
          decode_key = jwks_public_cert(jwks_x5c.first)
        elsif head[:alg] == 'HS256'
          decode_key = @client_secret
        else
          raise JWT::VerificationError, :id_token_alg_unsupported
        end

        # Docs: https://github.com/jwt/ruby-jwt#add-custom-header-fields
        decode_options = {
          algorithm: head[:alg],
          leeway: 30,
          verify_expiration: true,
          verify_iss: true,
          iss: @issuer,
          verify_aud: true,
          aud: @client_id,
          verify_not_before: true
        }

        # Docs: https://github.com/jwt/ruby-jwt#algorithms-and-usage
        JWT.decode(jwt, decode_key, true, decode_options)
      end

      # Get the decoded head segment from a JWT.
      # @return hash - The parsed head of the JWT passed, empty hash if not.
      def token_head(jwt)
        jwt_parts = jwt.split('.')
        return {} if blank?(jwt_parts) || blank?(jwt_parts[0])
        json_parse(Base64.decode64(jwt_parts[0]))
      end

      # Get the JWKS from the issuer and return a public key.
      # @param x5c string - X.509 certificate chain from a JWKS.
      # @return key - The X.509 certificate public key.
      def jwks_public_cert(x5c)
        x5c = Base64.decode64(x5c)

        # https://docs.ruby-lang.org/en/2.4.0/OpenSSL/X509/Certificate.html
        OpenSSL::X509::Certificate.new(x5c).public_key
      end

      # Return a specific key from a JWKS object.
      # @param key string - Key to find in the JWKS.
      # @param kid string - Key ID to identify the right JWK.
      # @return nil|string
      def jwks_key(key, kid)
        return nil if blank?(jwks[:keys])
        matching_jwk = jwks[:keys].find { |jwk| jwk[:kid] == kid }
        matching_jwk[key] if matching_jwk
      end

      private

      # Get a JWKS from the issuer
      # @return void
      def jwks
        jwks_uri = URI(@issuer + '.well-known/jwks.json')
        @jwks ||= json_parse(Net::HTTP.get(jwks_uri))
      end

      # Rails Active Support blank method.
      # @param obj object - Object to check for blankness.
      # @return boolean
      def blank?(obj)
        obj.respond_to?(:empty?) ? obj.empty? : !obj
      end

      # Parse JSON with symbolized names.
      # @param json string - JSON to parse.
      # @return hash
      def json_parse(json)
        JSON.parse(json, {:symbolize_names => true})
      end
    end
  end
end
