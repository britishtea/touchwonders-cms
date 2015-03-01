require "bundler/setup"
require "sinatra"
require "rest-client"

class CMS < Sinatra::Base
  configure do
    set :environment, ENV.fetch("ENVIRONMENT", "development")
    set :method_override, true
    set :views, File.expand_path("../../views", __FILE__)
    set :api_server, ENV.fetch("API_SERVER")

    use Rack::Session::Cookie, :secret => ENV.fetch("SESSION_SECRET")
  end

  helpers do
    def require_authentication!
      redirect "/login" unless logged_in?
    end

    def logged_in?
      session.key?(:api_key)
    end

    def with_key(hash)
      hash.merge("api_key" => session[:api_key])
    end

    def log_exception!
      exception = env['sinatra.error']

      logger.debug exception
      logger.debug exception.backtrace
    end
  end

  before do
    @client = RestClient::Resource.new(settings.api_server, :payload => {
      "api_key" => session["api_key"]
    })
  end

  get "/" do
    redirect url("/images")
  end

  # Authentication

  get "/login" do
    erb :login, :locals => { :csrf => session[:csrf], :errors => [] }
  end

  post "/login" do
    @client.options[:payload].merge!(params)

    begin
      response = @client["/api_key"].get
      body     = JSON.parse(response)

      session[:api_key] = body["response"]["api_key"]

      redirect "/"
    rescue RestClient::Unauthorized => exception
      status 401

      errors = JSON.parse(exception.http_body)["error"]["messages"]

      erb :login, :locals => { :csrf => session[:csrf], :errors => errors }
    end
  end

  get "/logout" do
    session.delete(:api_key)
    redirect url("/")
  end

  get "/images" do
    require_authentication!

    @client.options[:payload].merge!(params)
    response = @client["/images"].get
    images   = JSON.parse(response)

    erb :images, :locals => { :images => images["response"] }
  end

  # Uploading

  get "/image" do
    require_authentication!

    locals = { :csrf => session[:csrf], :image => {}, :errors => [] }
    erb :image_new, :locals => locals
  end

  post "/image" do
    require_authentication!

    params["image"] = params.fetch("image", {})[:tempfile]
    
    begin
      response = @client["/image"].post(with_key(params))
      body     = JSON.parse(response.body)

      redirect url("/image/#{body["response"]["id"]}")
    rescue RestClient::BadRequest => exception
      status 400

      locals = { 
        :csrf   => session[:csrf],
        :image  => params,
        :errors => JSON.parse(exception.http_body)["error"]["messages"]
      }
        
      erb :image_new, :locals => locals
    end
  end

  # Editing

  get "/image/:id" do |id|
    require_authentication!

    image = JSON.parse(@client["/image/#{id}"].get)

    if image.nil?
      error 404
    end

    locals = { :csrf => session[:csrf], :image => image["response"] }
    erb :image_edit, :locals => locals
  end

  put "/image/:id" do |id|
    require_authentication!

    @client["/image/#{id}"].put(with_key(params))
    redirect url("/image/#{id}")
  end

  delete "/image/:id" do |id|
    require_authentication!

    @client["/image/#{id}"].delete
    redirect url("/images")
  end


  error RestClient::Exception do
    log_exception!

    status 504
    erb :error
  end

  not_found do
    erb :not_found
  end

  error do
    log_exception!

    status 500
    erb :error
  end
end
