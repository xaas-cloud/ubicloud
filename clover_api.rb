# frozen_string_literal: true

class CloverApi < Roda
  include CloverBase

  plugin :default_headers,
    "Content-Type" => "application/json"

  plugin :hash_branches
  plugin :json
  plugin :json_parser

  autoload_routes("api")

  plugin :not_found do
    puts "1616161616161616"
    response.headers["Allow"] = "*"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "*"

    {
      error: {
        code: 404,
        title: "Resource not found",
        message: "Sorry, we couldn’t find the resource you’re looking for."
      }
    }.to_json
  end

  plugin :error_handler do |e|
    puts "323232323232323232"
    response.headers["Allow"] = "*"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "*"

    error = parse_error(e)

    {erroasdr: error}.to_json
  end

  plugin :rodauth do
    enable :argon2, :json, :jwt, :active_sessions, :login, :jwt_cors

    only_json? true
    use_jwt? true

    hmac_secret Config.clover_session_secret
    jwt_secret Config.clover_session_secret
    argon2_secret { Config.clover_session_secret }
    require_bcrypt? false
    # jwt_authorization_remove

    jwt_cors_allow_headers "*"
    jwt_cors_allow_methods "*"
    jwt_cors_allow_origin true
    jwt_cors_expose_headers "*"
  end

  route do |r|
    response.headers["Allow"] = "*"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "*"

    r.options do
      response.status = 200
      ""
    end

    r.rodauth
    rodauth.check_active_session
    rodauth.require_authentication

    @current_user = Account[rodauth.session_value]

    r.hash_branches("")
  end
end
