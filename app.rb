require 'rubygems'
require 'sinatra'
require 'rack-flash'
require 'haml'
require 'gdata'

use Rack::Flash
enable :sessions

set :password, ENV['password'] || 'secret'
set :username, ENV['username'] || 'secret'
set :picasa_password, ENV['picasa_password'] 
set :picasa_username, ENV['picasa_username']
set :token,'maketh1$longandh@rdtoremembeavecdesmotsenfrancaisr'

configure :production do
  require 'newrelic_rpm'
end

helpers do
  def admin? ; request.cookies[settings.username] == settings.token ; end
  def protected! ;redirect 'login' unless admin? ; end
end

# Creates a GData client for picasa.
def picasa_client
  client = GData::Client::Photos.new
  client.clientlogin(settings.picasa_username,settings.picasa_password)
  client
end


get '/' do
  haml :index, :layout => false
end

# Admin pages with list 
get '/admin' do
  protected!
  haml :admin
end

#GET login page
get '/login' do
  haml :login
end

#Check login and rediret to admin page
post '/login' do
  if params['username']==settings.username && params['password']==settings.password
    response.set_cookie(settings.username,:value => settings.token,:expires => Time.new + 3600) 
    redirect '/admin'
  else
    flash['error'] = "Login ou mot de passe incorrects"
    redirect '/login'
  end
end

get '/logout' do
  response.set_cookie(settings.username, false)
  flash['info'] = "Vous êtes déconnecté"
  redirect '/login'
end

get '/add' do
  protected!
  haml :add
end

post '/add' do
  protected!
  unless params[:image] && (tmpfile = params[:image][:tempfile]) && (name = params[:image][:filename])
    flash['error'] = "Merci de remplir l'ensemble des informations obligatoires" 
    redirect '/add'
  end
  file = Tempfile.new(['hello', '.jpg'])
  while blk = tmpfile.read(65536)
    file.write(blk)
  end
  client = picasa_client
  test_image = file.path
  mime_type = 'image/jpeg'
    
  response = client.post_file('http://picasaweb.google.com/data/feed/api/user/default/albumid/default', test_image, mime_type).to_xml
    
  puts response.elements["media:group"].elements["media:content"].attributes['url']
  puts response.elements["media:group"].elements["media:thumbnail[@width='288']"].attributes['url']
  tmpfile.close
  tmpfile.unlink
  edit_uri = response.elements["link[@rel='edit']"].attributes['href']
  #client.delete(edit_uri)


  flash['info'] = "nouvelle entrée créée"
  redirect '/admin'
  
end

