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
$datasource = ECGDemoServer.new.start

# Home screen
get '/' do
  send_file File.join(settings.public_folder, 'ajax.html')
end

# block and wait for next data
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
  ss = '<html><head></head><body><h1>Documentation</h1><ul>'
  StringIO.open(ss, 'w') do |sio|
    dir = Dir.new(File.join(settings.public_folder, 'docs'))
    dir.entries.grep(/^[^.]/).each do |fname|
      sio << '<li><a href="docs/' << fname << '">' << fname << '</a></li>'
    end
    sio << '</ul></body></html>'
  end
  ss
end

get "/docs/*.txt" do
  content_type :"text/plain"
  response['Cache-Control'] = 'no-cache'
  pass
end

get "/docs/*.pdf" do
  content_type :"application/pdf"
  response['Cache-Control'] = 'no-cache'
  pass
end
