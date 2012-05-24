#!/usr/bin/env ruby
=begin

Copyright (c) 2010 Ben Clarke <ben.t.clarke@gmail.com>

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

begin
	require File.join(File.dirname(__FILE__), 'torrent')
rescue LoadError
	puts <<EOF

I can't find torrent.rb!  It should be right beside me.
If you don't already have it, grab it from 
	
http://benclarke.ca/rubytorrent/

EOF

  exit
end

require 'digest/sha1'

def usage
	puts <<EOF
	This file hash checks torrent files.
	Usage: #{$0} torrent file_to_hashcheck
EOF
end

class HashChecker
	
	SHA_LEN = 20
	attr_accessor :files
	
	def initialize(file, piece_len, infohash)
		@dir = file
		@piece_len = piece_len
		@infohash = infohash
		@pieces = @infohash[:pieces]
		@files = []
		@file_idx = 0
		@piece_idx = 0
		@total_size = 0
		list_files
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
				:chunks => (size / @piece_len.to_f),
				:path => Array.new(subdirs ||= []) << File.basename(file)
			}
			
			@total_size += size
		end
	end
	
	def curr_file
		@files[@file_idx]
	end
	
	def total_chunks
		@pieces.length / SHA_LEN
	end
	
	def get_hash(idx = @piece_idx)
		start_idx = idx * SHA_LEN
		end_idx = start_idx + SHA_LEN
		@pieces[start_idx...end_idx]
	end
	
	def next_chunk
		
		@file = File.open(next_file) unless @file
		
		buf = @file.read(@piece_len) || ""
		while buf.length < @piece_len
			@file.close
			@file_idx += 1
			file = next_file
			break unless file
			@file = File.open(file)
			buf += @file.read(@piece_len - buf.length)
		end
		
		Digest::SHA1.digest(buf)
		
	end
	
	private
	
	def next_file
		file = @files[@file_idx]
		if File.directory? @dir
			file_name = File.join(@dir, file[:path].join('/'))
		else
			file_name = @dir
		end
		file_name
	end
	
end
  
if $0 != __FILE__
	puts "WARNING: check.rb is meant to be called directly, not required"
	return
else
  
  torrent, file = ARGV
  
  if torrent.nil? or file.nil?
    usage
    exit
  end
  
  File.open(torrent) {|f| @parser = Torrent::Parser.new(f) }
  hash = @parser.hash
  
  filename = File.basename(file)
  name = hash[:info][:name]
  files = hash[:info][:files]
  pieces = hash[:info][:pieces]
  piece_length = hash[:info][:'piece length']
  
  if File.directory?(file) && File.exists?(File.join(file, name)) && file != name
    file = File.join(file, name)
  end
  
  checker = HashChecker.new(file, piece_length, hash[:info])
  chunks = checker.total_chunks
  file = nil
  bytes = 0
  complete = false
  
  chunks.times do |i|
  	
  	curr_file = checker.curr_file
  	if file != curr_file
  		file = curr_file
  		print "\n#{file[:path]} \t\t"
  		print complete ? "1" : "0" if bytes % piece_length != 0
  		bytes += file[:length]
  	end
  	
  	hash = checker.get_hash i
  	chunk = checker.next_chunk
  	
  	complete = hash == chunk
  	print complete ? "1" : "0"
  	STDOUT.flush
  	
  end
  
end
