require 'rubygems'
require 'sinatra'
require 'rack-flash'

use Rack::Flash
enable :sessions

 
configure :production do
  require 'newrelic_rpm'
end
 
# Quick test
get '/' do
  flash[:notice] = "Your note has been saved"
  "Hello from the ratpack!"
end

