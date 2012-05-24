#!/usr/bin/env ruby
=begin

Copyright (c) 2007 Ben Clarke <ben.t.clarke@gmail.com>

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

require 'digest/sha1'
require 'optparse'

module Torrent
	AppVersion = 0.073
	class BEncHash < Hash
		alias_method :store, :[]=
		alias_method :each_pair, :each
		
		def initialize
			@keys = []
			@str = String.new
		end
		
		def []=(key, val)
			@keys << key
			super
		end
		
		def delete(key)
			@keys.delete(key)
			super
		end
		
		def each
			@keys.sort {|a,b| a.to_s <=> b.to_s}.each { |k| yield k, self[k] }
		end
		
		def each_key
			@keys.sort{|a,b| a.to_s <=> b.to_s}.each { |k| yield k }
		end
		
		def each_value
			@keys.sort{|a,b| a.to_s <=> b.to_s}.each { |k| yield self[k] }
		end
		
		def to_s
			dict self
			@str
		end
		
		private
		
		def str(str)
			@str += "#{str.length}:#{str}"
		end
		
		def int(i)
			@str += "i#{i}e"
		end
		
		def list(l)
			@str += "l"
			l.each {|x| add x}
			@str += "e"
		end
		
		def dict(h)
			@str += "d"
			h.each do |k,v|
				add k
				add v
			end
			@str += "e"
		end
		
		def add(x)
			if x.kind_of? Symbol
				str(x.to_s)
			elsif x.kind_of? String
				str(x)
			elsif x.kind_of? Fixnum or x.kind_of? Bignum
				int(x)
			elsif x.kind_of? Array
				list(x)
			elsif x.kind_of? Hash
				dict(x)
			end
		end
	end
	class AbstractGenerator
		attr_accessor :file, :files, :dir, :announce, :chunk_size, :private, :total_size, :total_processed
		def initialize(dir, file, announce, chunk_size, comment = nil, private = false)
			@file = file
			@dir = dir
			@chunk_size = chunk_size * 1024
			@comment = comment
			@private = private
			@announce = announce
			@buf = String.new
			@files = []
			@sha = Digest::SHA1.new
			@total_size = 0
			@total_processed = 0
			@hash = BEncHash.new
		end
		
		def init
			
			arr = @announce.flatten
			@hash[:'announce'] = arr[0]
			
			if arr.length > 1
				@hash[:'announce-list'] = @announce
			end
			
			@hash[:'created by'] = "German's Torrent Generator #{AppVersion}"
			@hash[:'creation date'] = Time.now.to_i
			@hash[:comment] = @comment unless @comment.nil?
			
			@hash[:info] = BEncHash.new
			
			if @files.length == 1
				@hash[:info][:length] = @files[0][:length]
			else
				arr = Array.new(@files)
				@hash[:info][:files] = arr
			end
			
			@hash[:info][:name] = File.basename(@dir) unless @dir.nil?
			@hash[:info][:'piece length'] = @chunk_size
			@hash[:info][:'pieces'] = ''
			@hash[:info][:private] = 1 if @private
		end
		
		def create_torrent
			if @file.kind_of? String
				File.open(@file, 'w'){|f| f << @hash.to_s }
				message "Wrote #{File.basename @file} (infohash #{@sha.hexdigest(@hash[:info].to_s)})"
			elsif @file.kind_of? IO or @file.kind_of? Tempfile
				@file.write @hash.to_s
			end
		end
		
		def list_files(file = @dir, subdirs = nil)
			if File.directory? file
				if subdirs.nil?
					dirs = []
				else
					dirs = Array.new(subdirs)
					dirs << File.basename(file)
				end
				arr = []
				Dir.new(file).each {|f| arr << f unless f[0].chr == '.'}
				arr.sort!{|a,b| a<=>b}
				arr.each do |f|
					list_files(File.join(file, f), dirs)
				end
			else
				
				size = File.size(file)
				
				@files << {
					:length => size,
					:path => Array.new(subdirs ||= []) << File.basename(file)
				}
				
				@total_size += size
			end
		end
	
		def hash_file
			@files.each{|f| do_hash f}
		end
		
		def do_hash(file)
			if File.directory? @dir
				file_name = File.join(@dir, file[:path].join('/'))
			else
				file_name = @dir
			end
			last = file == @files[-1]
			
			size = file[:length]
			chunks = (size.to_f / @chunk_size).ceil
	
			File.open(file_name, 'r') do |f|
				i=0
				
				loop do
					l = @buf.length
					d = f.read(@chunk_size - l)
					@buf << d unless d.nil?
					@total_processed += @buf.length - l

					nf = (chunks == 0) ? 1.0 : i.to_f / chunks.to_f
					nt = (@total_size == 0) ? 1.0 : @total_processed.to_f / @total_size.to_f 

					progress_update(file[:path][-1], nf, nt)

					if @buf.length == @chunk_size || last
						@hash[:info][:pieces] << @sha.digest(@buf)
						break if last && @buf.length < @chunk_size
						@buf = ''
					else
						break
					end
					i += 1
				end
			end
		end
		def clear
			@files = []
			@total_size = 0
			@hash = BEncHash.new
			reset
			init
		end
		def reset
			@buf = String.new
			@total_processed = 0
			progress_update nil, 0, 0
		end
		def progress_update(file, pct_file, pct_total);end
		def message(message);end
	end
	class Generator < AbstractGenerator
		Spinner = [ '|', '/', '-', '\\' ]
		def progress_update(file, pct_file, pct_total)
			
			x = [25, (pct_total * 25).to_i].min
			y = [25, (pct_file * 25).to_i ].min

			x_bar = ('=' * x) + (' ' * (25 - x))
			y_bar = ('=' * y) + (' ' * (25 - y))
			
			@i ||= 0
			
			print "\033[31;1m#{Spinner[@i % Spinner.length]}"
			printf "\033[33;1m %20.20s", file
			print "\033[m |\033[36;1m#{y_bar}\033[m|"
			print "\033[m |\033[36;1m#{x_bar}\033[m|\r"
			
			@i += 1
		end
		def message(message)
			puts
			puts message
		end
	end
	class Parser
	
		attr_accessor :hash
		
		BufSize = 1024
		
		def initialize(stream)
			@buf_size = BufSize
			@buf = String.new
			@buf_ptr = 0
			
			@stream = stream
			@hash = parse
		end
			
		def parse
			ret = nil
			until (c = next_char(false)) == nil
				case c
					when 'd' then
						ret = BEncHash.new
						k = nil
						until (x = parse) == :end
							unless k.nil?
								ret[k] = x
								k = nil
							else
								k = x.intern
							end
						end
						
					when 'l' then
						ret = []
						until (x = parse) == :end
							ret << x
						end
						
					when 'i' then
						ret = read_to('e').to_i
						
					when /[0-9]/
						len = c << read_to(':')
						ret = ''
						len.to_i.times {|i| ret << next_char }
						
					when 'e' then
						ret = :end
						
					else
						raise "Invalid torrent file: " + 
							"encountered unexpected character '#{c}'"
					
				end
				return ret
			end
		end
			
		def read_to(x)
			ret = ""
			until (c = next_char) == x
				ret << c
			end
			ret
		end
			
		def next_char(err = true)
			
			if @buf_ptr >= @buf.length
				@stream.read(@buf_size, @buf)
				@buf_ptr = 0
			end
			
			c = @buf[@buf_ptr].chr
			@buf_ptr += 1
			
			raise "Unexpected EOF" if err and c.nil?
			return c
		end
	end
end

class File
	GIGA_SIZE = 1073741824.0
	MEGA_SIZE = 1048576.0
	KILO_SIZE = 1024.0
	def self.human_size(size, precision = 2) 
		case 
			when size == 1 then "1b" 
			when size < KILO_SIZE then "%db" % size 
			when size < MEGA_SIZE then "%.#{precision}fkB" % (size / KILO_SIZE) 
			when size < GIGA_SIZE then "%.#{precision}fMB" % (size / MEGA_SIZE) 
			else "%.#{precision}fGB" % (size / GIGA_SIZE) 
		end 
	end
end

if __FILE__ == $0
	
	options = {
		'chunk size' => 256
	}
	
	parser = OptionParser.new do |opts|
	
		opts.banner = "RubyTorrent #{Torrent::AppVersion}"
		opts.separator " "
		opts.separator "Usage: #{__FILE__} [options]"
		opts.separator " "
		opts.separator "Specific options:"
		
		opts.on(
			"-a", 
			"--announce URL[,URL...]",
			"Comma separated tracker announce URLs",
			"  define one tier of an announce list *"
		) do |url|
			(options['announce'] ||= []) << url.split(',')
		end
		
		opts.on(
			"-f",
			"--file FILE",
			"File or directory to create torrent from"
		) do |file|
			options['file'] = file
		end
		
		opts.on(
			"-o",
			"--output FILE",
			"File to save torrent as"
		) do |file|
			options['torrent'] = file
		end
		
		opts.on(
			"-p",
			"--piece-size [SIZE]",
			OptionParser::DecimalInteger,
			"Specify piece size in kilobytes",
			"  (Defaults to 256 if not specified)"
		) do |size|
			options['chunk size'] = size
		end
		
		opts.on(
			"-c",
			"--comment [COMMENT]",
			"Comment for torrent"
		) do |c|
			options['comment'] = c
		end
		
		opts.on(
			"-P",
			"--[no-]private",
			"Mark torrent private"
		) do |p|
			options['private'] = p
		end
		
		opts.on(
			"-q",
			"--[no-]quiet",
			"Generate no output"
		) do |q|
			options['quiet'] = q
		end

		opts.on("-h", "--help", "Show this message") do
			puts opts
			exit
		end
		
		opts.separator " "
		opts.separator "* For torrents with multiple announce URLS, "
		opts.separator "trackers specified in the same comma separated list"
		opts.separator "will be hit in random order.  Trackers specified in "
		opts.separator "different lists will be hit in the order they are specified."
		opts.separator " "
		opts.separator "Example 1: try tracker1, then tracker2, then tracker3"
		opts.separator "  -a tracker1 -a tracker2 -a tracker3"
		opts.separator " "
		opts.separator "Example 2:  try tracker1, then either tracker2 or tracker3"
		opts.separator "  -a tracker1 -a tracker2,tracker3"

	end
	
	parser.parse!(ARGV)
	
	if options['file'].nil? or options['torrent'].nil? or options['announce'].nil?
		puts parser
	else
		
		if options['quiet']
			cls = Torrent::AbstractGenerator
		else
			cls = Torrent::Generator
		end
		
		generator = cls.new(
			options['file'],
			options['torrent'],
			options['announce'], 
			options['chunk size'],
			options['comment'],
			options['private']
		)
		generator.list_files
		generator.init
		generator.hash_file
		generator.create_torrent
		
	end
end
