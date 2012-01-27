# $Id$
# Web server (using Sinatra framework) for connectBlue ECG demo board
require 'rubygems'
require 'cgi'
require 'fileutils'
require 'pp'
require 'sinatra'
require 'ecgdemo'

set :environment, :development
enable :dump_errors, :lock
disable :sessions
$webpublic = settings.public_folder
$datasource = ECGDemo.new

# Home screen
get '/data.json' do
  last_sample = (request.cookies['last_sample'] || "0").to_i
  # get all samples since last one
  response.set_cookie("last_sample", last_sample+1)
  content_type :json
  $datasource.samplesSince(last_sample).to_json
end

# documentation
get "/docs" do
  filenames = Dir.glob($webpublic + "/docs/*.*")
  filenames.each 
end
