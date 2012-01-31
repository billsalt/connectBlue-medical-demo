# Web server (using Sinatra framework) for connectBlue ECG demo board
# $Id$
require 'rubygems'
require 'cgi'
require 'fileutils'
require 'pp'
require 'sinatra'

require './ecgdemo'

set :environment, :development
enable :dump_errors, :lock
disable :sessions
$webpublic = settings.public_folder
$datasource = ECGDemoServer.new.start

# Home screen
get '/data.json' do
  last_sample = (params['last_sample'] || "0").to_i
  # get all samples since last one
  content_type :json
  (j,t) = $datasource.jsonSince(last_sample)
  j
end

get '/status.json' do
  content_type :json
  $datasource.status
end

# documentation
get "/docs" do
  filenames = Dir.glob($webpublic + "/docs/*.*")
  filenames.inspect
end
