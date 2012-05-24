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
Usage: #{$0} file.torrent
EOF
end

def val(name, value)
	puts "%30s: %s" % [ name, value ]
end

if $0 != __FILE__
	puts "WARNING: infohash.rb is meant to be called directly, not required"
else
	file = ARGV[0]
	if file.nil?
		usage
		exit
	end
	
	File.open(file) {|f| @parser = Torrent::Parser.new(f) }
	hash = @parser.hash
	
	val "File", File.basename(file)
	val "Infohash", Digest::SHA1.hexdigest(hash[:info].to_s)
	val "Default name", hash[:info][:name]
	val("Size", File.human_size(hash[:info][:length].to_i)) if hash[:info][:length]
	if hash[:info][:files]
		title = "Files:"
		hash[:info][:files].each do |f|
			puts "%31s %s (%s)" % [ title, File.join(*(f[:path])), File.human_size(f[:length].to_i) ]
			title = ""
		end
	end

	val "Primary Announce URL", hash[:announce]
	
	if hash[:'announce-list']
		title = "Announce List:"
		i=1
		hash[:'announce-list'].each do |tier|
			puts "%31s %s" % [ title, "Tier #{i}:" ]
			puts ("%36s" % "") << tier.join("\n%35s " % "")
			i += 1
			title = ""
		end
	end	
	
	val "Chunk Size", "#{hash[:info][:'piece length'].to_i / 1024}kB"
	val "Created By", hash[:'created by']
	val "Creation Date", Time.at(hash[:'creation date'].to_i)
	val "Comment", hash[:comment] if hash[:comment]
end
