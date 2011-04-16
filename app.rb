require 'rubygems'
require 'sinatra'
require 'rack-flash'
require 'haml'

use Rack::Flash
enable :sessions

set :token,'maketh1$longandh@rdtoremembeavecdesmotsenfrancaisr'

configure :development do
  set :username,'toto'
  set :password,'tata'
end

configure :production do
  require 'newrelic_rpm'
end

helpers do
  def admin? ; request.cookies[settings.username] == settings.token ; end
  def protected! ;redirect 'login' unless admin? ; end
end

get '/' do
  haml :index
end

# Quick test
get '/admin' do
  protected!
  haml :admin
end

get '/login' do
  haml :login
end

post '/login' do
  if params['username']==settings.username && params['password']==settings.password
    response.set_cookie(settings.username,:value => settings.token,:expires => Time.new + 3600) 
    redirect '/admin'
  else
    flash['error'] = "Username or Password incorrect"
     redirect '/login'
  end
end

get '/logout' do
  response.set_cookie(settings.username, false)
  redirect '/login'
end

