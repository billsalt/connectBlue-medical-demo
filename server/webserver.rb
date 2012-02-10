# Web server (using Sinatra framework) for connectBlue ECG demo board
# $Id$
BEGIN { $: << File.dirname(File.expand_path($0)) }

require 'rubygems'
require 'cgi'
require 'fileutils'
require 'pp'
require 'sinatra'

require 'ecgdemo'

$nostore = development?

enable :dump_errors, :logging, :run
disable :sessions, :static, :lock

helpers do
  def send_public(*args)
    send_file File.join(settings.public_folder, args.join('.'))
  end
  def send_doc(*args)
    send_file File.join(settings.public_folder, "docs", args.join('.'))
  end
end

$datasource = ECGDemoDataSource.new.start

# Home screen
get '/' do
  cache_control(:no_store) if $nostore
  send_public('cbdemo.html')
end

# block and wait for next data
get '/data.json' do
  cache_control(:no_store)
  last_sample = (params['last_sample'] || "0").to_i
  # get all samples since last one
  content_type :json
  (j,t) = $datasource.jsonSince(last_sample)
  j
end

get '/settings' do
  settings.inspect
end

get '/status.json' do
  cache_control(:no_store)
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

# get "/docs/*.txt" do
#   content_type("text/plain")
#   pass
# end
# 
# get "/docs/*.pdf" do
#   content_type("application/pdf")
#   pass
# end

# serving files from public folder

get "/*.*" do |path, ext|
  cache_control(:no_store) if $nostore && (path =~ /^cbdemo/)
  send_public(path,ext)
end

