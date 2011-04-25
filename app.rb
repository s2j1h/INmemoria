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
  property :nom,                  String
  property :dateNaissance,        String
  property :dateDeces,            String
  property :commentaires,         Text
  property :urlImagePleine,       Text
  property :urlImageReduite,      Text
  property :urlImageTresReduite,  Text
  property :urlImageEdit,         Text
end

DataMapper.auto_upgrade!
DataMapper::Model.raise_on_save_failure = false #permet de savoir si tout est bien sauvegardé, à utiliser avec rescue

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

get '/admin/add' do
  protected!
  haml :add
end

post '/admin/add' do
  protected!
  if params[:nom] == "" || params[:dateDeces] == ""
    redirect '/admin/add', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
  end

  unless params[:image] && params[:image][:tempfile] && params[:image][:filename]
    redirect '/admin/add', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
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
    redirect '/admin', :error => "Une erreur a empêché la sauvegarde de l'hommage - merci de contacter votre admin préféré"
  end
end

get '/admin/edit/:id' do
  protected!
  @hommage = Hommage.get(params[:id])
  haml :edit
end

post '/admin/edit/:id' do
  protected!
  if params[:nom] == "" || params[:dateDeces] == ""
    redirect '/admin/edit/params[:id]', :error =>  "Merci de remplir l'ensemble des informations obligatoires" 
  end
  hommage = Hommage.get(params[:id])
  nom = params[:nom]
  dateDeces = params[:dateDeces] 
  dateNaissance =  params[:dateNaissance] 
  commentaires = params[:commentaire]

  #pas de modif d'image
  unless params[:image] && params[:image][:tempfile] && params[:image][:filename]
      if hommage.update(    
          :nom => nom, 
          :dateNaissance => dateNaissance, 
          :dateDeces => dateDeces, 
          :commentaires => commentaires
          )
        redirect '/admin', :notice => "L'hommage a bien été modifié"
      else
        puts hommage.errors.inspect
        redirect '/admin', :error => "Une erreur a empêché la modification de l'hommage - merci de contacter votre admin préféré"
      end
  end
  #besoin de changer l'image - d'abord on supprime l'ancienne
  client = picasa_client
  client.delete(hommage.urlImageEdit)

  #puis on crée la nouvelle
  tmpfile = params[:image][:tempfile]
  filename = params[:image][:filename]

  file = Tempfile.new([filename, '.jpg'])
  while blk = tmpfile.read(65536)
    file.write(blk)
  end
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

  puts "UPDATE en cours"
  if hommage.update(
    :nom => nom, 
    :dateNaissance => dateNaissance, 
    :dateDeces => dateDeces, 
    :commentaires => commentaires, 
    :urlImagePleine => urlImagePleine, 
    :urlImageReduite => urlImageReduite,
    :urlImageTresReduite => urlImageTresReduite,
    :urlImageEdit => urlImageEdit
    )
    redirect '/admin', :notice => "L'hommage a bien été modifié"
  else
    puts hommage.errors.inspect
    redirect '/admin', :error => "Une erreur a empêché la modification de l'hommage - merci de contacter votre admin préféré"
  end
end


get '/admin/delete/:id' do
  protected!
  @hommage = Hommage.get(params[:id])
  unless @hommage
   redirect '/admin', :error => "L'hommage n'existe pas - merci de contacter votre admin préféré"
  end
  urlImageEdit = @hommage.urlImageEdit
  if @hommage.destroy
    client = picasa_client
    client.delete(urlImageEdit)
    redirect '/admin', :notice => "L'hommage a été supprimé avec succès"
  else
    puts @hommage.errors.inspect
    redirect '/admin', :error => "Une erreur a empêché la suppression de l'hommage - merci de contacter votre admin préféré"
  end
end
   




