require 'rubygems'
require 'sinatra'
require 'rack-flash'
require 'haml'
require 'gdata'
require 'sinatra/redirect_with_flash'
require 'data_mapper'

use Rack::Flash, :sweep => true
enable :sessions

set :password, ENV['password'] || 'secret'
set :username, ENV['username'] || 'secret'
set :picasa_password, ENV['picasa_password'] 
set :picasa_username, ENV['picasa_username']
set :token,'maketh1$longandh@rdtoremembeavecdesmotsenfrancaisr'

configure :development do
  DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/development.db")
end

configure :production do
  require 'newrelic_rpm'
  DataMapper.setup(:default, ENV['DATABASE_URL'])
end


class Hommage
  include DataMapper::Resource  
  property :id,                   Serial
  property :nom,                  String, :required => true
  property :dateNaissance,        String
  property :dateDeces,            String, :required => true
  property :commentaires,         Text
  property :urlImagePleine,       Text, :required => true
  property :urlImageReduite,      Text, :required => true
  property :urlImageTresReduite,  Text, :required => true
  property :urlImageEdit,         Text, :required => true
end

DataMapper.auto_upgrade!
#DataMapper::Model.raise_on_save_failure = true #permet de savoir si tout est bien sauvegardé, à utiliser avec rescue

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
  @hommages = Hommage.all
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
    flash[:error] = "Login ou mot de passe incorrect"
    redirect '/login', :error => "Login ou mot de passe incorrect"
  end
end

get '/logout' do
  response.set_cookie(settings.username, false)
  flash[:notice] = "Vous êtes déconnecté"
  haml :login
end

get '/add' do
  protected!
  haml :add
end

post '/add' do
  protected!
  if params[:nom] == "" || params[:dateDeces] == ""
    redirect '/add', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
  end

  unless params[:image] && params[:image][:tempfile] && params[:image][:filename]
    redirect '/add', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
  end
  tmpfile = params[:image][:tempfile]
  filename = params[:image][:filename]

  file = Tempfile.new([filename, '.jpg'])
  while blk = tmpfile.read(65536)
    file.write(blk)
  end
  client = picasa_client
  test_image = file.path
  mime_type = 'image/jpeg'
    
  response = client.post_file('http://picasaweb.google.com/data/feed/api/user/default/albumid/default', test_image, mime_type).to_xml
    
  urlImagePleine = response.elements["media:group"].elements["media:content"].attributes['url']
  urlImageTresReduite = response.elements["media:group"].elements["media:thumbnail[@width='144']"].attributes['url']
  urlImageReduite = response.elements["media:group"].elements["media:thumbnail[@width='288']"].attributes['url']
  urlImageEdit = response.elements["link[@rel='edit']"].attributes['href']
  #client.delete(edit_uri)
  tmpfile.close
  tmpfile.unlink

  nom = params[:nom]
  dateDeces = params[:dateDeces] 
  dateNaissance =  params[:dateNaissance] 
  commentaires = params[:commentaire]

  hommage = Hommage.create(
    :nom => nom, 
    :dateNaissance => dateNaissance, 
    :dateDeces => dateDeces, 
    :commentaires => commentaires, 
    :urlImagePleine => urlImagePleine, 
    :urlImageReduite => urlImageReduite,
    :urlImageTresReduite => urlImageTresReduite,
    :urlImageEdit => urlImageEdit
  )
  if hommage.save
     redirect '/admin', :notice => "Une nouvelle entrée a été créée"
  else
    puts hommage.errors.inspect
    redirect '/admin', :error => "Une erreur a empéché la sauvegarde de l'hommage - merci de contacter votre admin préféré"
  end
   
end



