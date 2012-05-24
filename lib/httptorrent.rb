#!/usr/bin/env ruby
=begin

Copyright © 2007 Ben Clarke <ben.t.clarke@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=end

require 'webrick'
require 'torrent'
require 'erb'
require 'builder'
require 'yaml'
require 'ostruct'
require 'tempfile'

Thread.abort_on_exception = true

module Torrent
	ConfigFile = File.expand_path("~/.httptorrent")
	class AuthHandler<WEBrick::HTTPServlet::FileHandler
		def service(request, response)
			Http.auth.authenticate(request, response) if Http.auth
			super
		end
	end
	class DirListServlet<WEBrick::HTTPServlet::AbstractServlet
		DisallowedDirs = [ 
			/^dev$/, /^sys$/, /^proc$/, 
			/^etc$/, /passwd/, /^\./, /^lost\+found$/,
			/^root$/, /^boot$/, /^tmp$/
		]
		
		def initialize(config)
			super
			@file_root = Http.config('file_root')
			@file_root ||= File.expand_path('~')
		end
		
		def service(request, response)
			Http.auth.authenticate(request, response) if Http.auth
			super
		end
		
		def do_GET(request, response)

			dir = @file_root + request.query['dir']
			
			unless accept_file dir
				response.status = 403
				response['Content-Type'] = "text/plain"
				response.body = "You are not allowed to view #{dir}"
				return
			end
			
			response['Content-Type'] = "text/xml"
			response.status = 200
			
			doc = Builder::XmlMarkup.new
			doc.instruct!
			
			response.body = doc.dirList do
				arr = []
				Dir.foreach(dir) do |d|
					next unless File.readable?(File.join(dir, d))
					if accept_file d
						arr << d
					end
				end
				
				arr.sort! do |a,b| 
					da = File.join(dir, a)
					db = File.join(dir, b)
					if File.directory?(da) and not File.directory?(db)
						-1 
					elsif File.directory?(db) and not File.directory?(da)
						1 
					else
						a.downcase<=>b.downcase
					end
				end
				
				arr.each do |d| 
					if File.directory? File.join(dir, d)
						doc.dir d
					else
						doc.file d
					end
				end
			end
		end
		def accept_file(file)
			files = file.split '/'
			files.each do |f|
				DisallowedDirs.each do|d|
					if f =~ d
						return false
					end
				end
			end
			return true
		end
	end
	class CreatorServlet < WEBrick::HTTPServlet::AbstractServlet
		@@sessions = {}
		def service(request, response)
			Http.auth.authenticate(request, response) if Http.auth
			set_cookie(request, response)
			super
		end
		
		def do_GET(request, response)
			
			generator = @session.generator
			
			unless generator
				
				response['Content-Type'] = "text/xml"
				response.status = 200
				
				error_doc response, "Generator was not in session"
				return
			end
			
			begin
				if generator.complete
					
					response.status = 200
					
					if request.query['dl'] == '1'
					
						response['Content-Type'] = "application/x-bittorrent"
						response['Content-Disposition'] = "attachment; filename=\"#{File.basename(generator.dir)}.torrent\""
						
						File.open(generator.file.path, 'r') do |f|
							response.body = f.read
						end
						
					else
						
						response['Content-Type'] = "text/xml"
						complete_doc response, generator
						
					end
				else
					
					response['Content-Type'] = "text/xml"
					response.status = 200
					
					update_doc response, generator
				end
			rescue
			
				response['Content-Type'] = "text/xml"
				response.status = 200
			
				error_doc response, "#{$!}"
			end
		end
		
		def complete_doc(response, generator)
			doc = Builder::XmlMarkup.new
			doc.instruct!
			response.body = doc.done
		end
		
		def update_doc(response, generator)
			doc = Builder::XmlMarkup.new
			doc.instruct!
			response.body = doc.update(
				{ :file => generator.file_progress, :total => generator.total_progress },
				generator.curr_file
			)
		end
		
		def error_doc (response, message)
			doc = Builder::XmlMarkup.new
			doc.instruct!
			response.body = doc.error message
		end

		def do_POST(request, response)

			query = request.query

			files = query['files'].split(';')
			trackers = query['trackers'].split(';')
			chunk_size = query['csize'].to_i
			private = (query['private'] == 'on')
			
			root = Http.config('file_root');

			files.collect!{|x| File.join(root, x)}
			trackers.collect!{|x| [ x ] }
			
			dir = nil
			if files.length == 1
				dir = files[0]
			else
# figure out the common base of all these files
				files.sort!{|a,b| a.count('/') < b.count('/') ? -1 : 1 }
				dir = File.dirname(files[0])
			end
			
			puts "Files is #{files.inspect}"
			puts "Trackers is #{trackers.inspect}"
			puts "Chunk Size is #{chunk_size}"
			puts "Private is #{private}"
			puts "Dir is #{dir}"
			
			tmp = Tempfile.new('torrent')

			@session.generator = SimpleGenerator.new(
				dir,
				tmp,
				trackers,
				chunk_size,
				nil,
				private
			)
			
			torrent_dir = Http.config(:torrent_dir)
			torrent_dir ||= "~"
			torrent_dir = File.expand_path(torrent_dir)
			
			filename = File.join(torrent_dir, File.basename(@session.generator.dir))
			
			puts " will write #{filename}"

			thr = Thread.new {
			
				files.each do |f|
					@session.generator.list_files f
				end
			
				@session.generator.init
				@session.generator.hash_file 
				@session.generator.create_torrent
				
# TODO copy temp file to permanent dir

				begin
					tmp.rewind
					File.open("#{filename}.torrent",'w') do |f|
						f.write tmp.read
					end
				rescue
					puts "Error writing torrent file: #{$!}"
				ensure
					tmp.close
				end

				@session.generator.complete = true
				
			}
			thr.priority = -1
			
			sleep 1.0
			
			do_GET(request, response)

		end
		def set_cookie(request, response)
			@cookie = nil
			if request.cookies.length > 0
				request.cookies.each do |cookie|
					if cookie.name == "sessionid"
						@cookie = cookie
						break
					end
				end
			end
			unless @cookie and @@sessions[@cookie.value]
				@cookie = WEBrick::Cookie.new("sessionid", session_key)
				@@sessions[@cookie.value] = OpenStruct.new
			end
			@session = @@sessions[@cookie.value]
			response.cookies << @cookie
		end
		def session_key
			key = ""
			20.times{key << rand(255).chr}
			key << Time.now.to_i.to_s
			return Digest::SHA1.hexdigest(key)
		end
	end
	class SimpleGenerator < AbstractGenerator
		attr_accessor :curr_file, :file_progress, :total_progress, :msg, :complete
		def progress_update(file, pct_file, pct_total)
			
			@curr_file = file
			@file_progress = pct_file
			@total_progress = pct_total
			
		end
		def message(message)
			@msg = message
			puts message
		end
	end
	class Http
		def self.start_server
			begin
				@@config = YAML.load_file Torrent::ConfigFile
			rescue
				@@config = {
					'port' => 2000,
					'bind' => '127.0.0.1',
					'doc_root' => Dir.pwd + "/htdocs"
				}
				File.open(Torrent::ConfigFile, 'w'){|f| YAML.dump(@@config, f)}
			end
			
			pass = config 'htpasswd_file'
			if pass
				passdb = WEBrick::HTTPAuth::Htpasswd.new(pass)
				@@auth = WEBrick::HTTPAuth::BasicAuth.new(
					:UserDB => passdb,
					:Realm => "RubyTorrent #{AppVersion}"
				)
			else
				@@auth = nil
			end
			
			server = WEBrick::HTTPServer.new( 
				:Port => @@config['port'],
				:BindAddress => @@config['bind']
			)
			server.mount('/', AuthHandler, @@config['doc_root'])
			server.mount('/dir_list', Torrent::DirListServlet)
			server.mount('/create_torrent', Torrent::CreatorServlet)
			
			trap("INT") {
				server.shutdown
			}
			server.start		
		end
		def self.auth
			@@auth
		end
		def self.config(param)
			@@config[param]
		end
	end
end

if __FILE__ == $0
	Torrent::Http.start_server
end
