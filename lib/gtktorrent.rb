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

begin
	require 'gtk2'
rescue LoadError
	puts <<EOF 

It looks like you don't have the GTK2 bindings for ruby installed.
If you are on a debian derivative distribution such as Ubuntu, you
can install them with 

apt-get install libgtk2-ruby

Otherwise, releases and more information can be found at 

http://ruby-gnome2.sourceforge.jp/

EOF

exit
end

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

begin
	require 'yaml'
rescue LoadError
	puts <<EOF
	
I can't find the ruby yaml library.  Without it,
I can't save your information for next time :(

EOF
end

Thread.abort_on_exception = true

module Torrent
	Title = "RubyTorrent #{AppVersion}"
	Columns = [ "Filename", "Size" ]
	ColumnSizes = [ 475, 80 ]
	ChunkSizes = [ 64, 128, 256, 512, 1024, 2048, 4096 ]
	ConfigFile = "~/.rubytorrent"
	class GtkGenerator < AbstractGenerator
		def initialize()
			@sha = Digest::SHA1.new
			@total_size = 0
			@total_processed = 0
			@hash = BEncHash.new
			@buf = String.new
			@files = []
			
# this speeds up hashing by not making
# the hashing thread wait for GTK to
# update the progress bars

			@thr = Thread.new do
				loop do
					sleep 0.05
					
					if @total_bar && @total_pct
						@total_bar.fraction = [ 1.0, @total_pct ].min
					end
					
					if @file_bar && @file_pct
						@file_bar.fraction = [ 1.0, @file_pct ].min
					end
					
					if @status
						@status.pop @context_id
						if @curr_file
							@status.push(@context_id, GLib.filename_to_utf8(@curr_file))
						end
					end
				end
			end
		end
		def set_controls(total_bar, file_bar, status, context_id)
			@total_bar = total_bar
			@file_bar = file_bar
			@status = status
			@context_id = context_id
		end
		def progress_update(file, pct_file, pct_total)
			@file_pct = pct_file
			@total_pct = pct_total
			@curr_file = file
		end
		def message(message)
			@curr_file = message
		end
	end
	class GtkMain
		def initialize
			
			load_prefs
			
			@generator = GtkGenerator.new
			@window = Gtk::Window.new Title		
			@announce = Gtk::Entry.new
			@file_list = Gtk::ListStore.new(String, String)
			@folder_button = Gtk::Button.new("Add Folder")
			@files_button = Gtk::Button.new("Add Files")
			@clear_button = Gtk::Button.new("Clear File List")
			@chunk_sizes = Gtk::ComboBox.new
			@msglabel = Gtk::Statusbar.new
			@context_id = @msglabel.get_context_id("foldername")
			@file_progress = Gtk::ProgressBar.new
			@total_progress = Gtk::ProgressBar.new
			@private = Gtk::CheckButton.new("Private")
			@create_button = Gtk::Button.new("Create and Save Torrent")
			
			@window.set_default_size(640, 400)
			@window.role="main"
			@window.signal_connect("destroy") {
				save_prefs
				Gtk.main_quit
			}
			
			@generator.set_controls(@total_progress, @file_progress, @msglabel, @context_id)
			
			@private.active = @conf[:private] unless @conf[:private].nil?

			vbox = Gtk::VBox.new
			
			vbox.pack_start build_menu, false, false, 0
			
			label = Gtk::Label.new
			label.set_markup "<big><b>#{Title}</b></big>"
			label.set_alignment 0, 0
			label.set_padding 10, 10
			vbox.pack_start label, false, false, 0
			
			frame = Gtk::Frame.new('Create Torrent')
			frame_vbox = Gtk::VBox.new false, 10
			
			expander = Gtk::Expander.new("Announce URLs")
			frame_vbox.pack_start expander, false, false, 0
			
			[ "key-release-event", "paste-clipboard", 
				"cut-clipboard", "insert-at-cursor", "focus-out-event" ].each do |evt|
				@announce.signal_connect(evt) do
					@create_button.sensitive = accept_input?
					false
				end
			end
			
			url = @conf[:announce]
			if url and url.kind_of? String
				@announce.text = @conf[:announce]
			elsif url.kind_of?(Array) and url.flatten.length == 1
				@announce.text = url.flatten[0]
			end
			
			frame_vbox.pack_start @announce, false, false, 0
			
			widgets_built = false
			multi_announce=Gtk::VBox.new false, 10
			frame_vbox.pack_start multi_announce, false, false, 0
			
			expander.signal_connect("notify::expanded") {
				if expander.expanded?
					unless widgets_built
						create_announce_box multi_announce
						widgets_built = true
					end
					multi_announce.show_all
				else
					multi_announce.hide_all
					@window.resize(640, 400)
				end
			}
			
			label = Gtk::Label.new("Files")
			label.set_alignment 0, 1
			frame_vbox.pack_start label, false, false, 0
			
			list = Gtk::TreeView.new(@file_list)
			list.height_request = 150
			list.selection.mode = Gtk::SELECTION_MULTIPLE
			
			menu = Gtk::Menu.new
			
			item = Gtk::MenuItem.new("Remove file(s) from torrent")
			item.signal_connect("activate") {
				files=[]
				list.selection.selected_each{|model,path,iter|
					files << [ path, Gtk::TreeRowReference.new(model, path) ]
				}
				
				files.each do |arr|
					path, ref = arr
					idx = path.indices[0]
					f = @generator.files[idx]
					@generator.total_size -= f[:length]
					@generator.files[idx] = nil
					@file_list.remove(@file_list.get_iter(ref.path))
				end
				
				@generator.files.compact!
				
				if @generator.files.length == 1
					new_file = @generator.files[0][:path].join("/")
					@generator.dir = File.join(@generator.dir, new_file)
					fname = GLib.filename_to_utf8(File.basename(@generator.dir))
					@generator.message "Suggested file name will be \"#{fname}\""
				end
				
				@create_button.sensitive = accept_input?
			}
			
			menu.append(item)
			menu.show_all
			
			renderer = Gtk::CellRendererText.new
			i=0
			Columns.each do |c|
				col = Gtk::TreeViewColumn.new(c, renderer, :text => i)
				col.resizable=true
				col.min_width=ColumnSizes[i]
				list.append_column(col)
				i += 1
			end
			
			frame_vbox.pack_start(Gtk::ScrolledWindow.new.add(list), true, true, 0)
			
			list.signal_connect("button_press_event") do |widget, event|
				if event.button == 3
					x=false
					list.selection.selected_each{x=true;break}
					menu.popup(nil, nil, event.button, event.time) if x
				end
			end
			
			hbox = Gtk::HBox.new(false, 10)
			
			@folder_button.signal_connect("clicked") {
				file_add_dialog(Gtk::FileChooser::ACTION_SELECT_FOLDER,false)
			}
			
			@files_button.signal_connect("clicked") {
				file_add_dialog(Gtk::FileChooser::ACTION_OPEN,true)
			}
			
			hbox.pack_start(@folder_button, true, false, 0)
			hbox.pack_start(@files_button, true, false, 0)
			
			@clear_button.signal_connect("clicked") {
				@generator.clear
				@file_list.clear
				
				@folder_button.sensitive = true
				@files_button.sensitive = true
				@create_button.sensitive = accept_input?
			}
			
			hbox.pack_start(@clear_button, true, false, 0)
			frame_vbox.pack_start hbox, false, false, 0
			
			ChunkSizes.each {|s| @chunk_sizes.append_text pretty_size(s * 1024, false)}
			@chunk_sizes.active=2
			
			hbox = Gtk::HBox.new false, 10
			label = Gtk::Label.new "Chunk Size"
			label.set_alignment 1, 0.5
			
			c_hbox = Gtk::HBox.new false, 5
			
			c_hbox.pack_start label, false, true, 0
			c_hbox.pack_start @chunk_sizes, false, false, 0
			hbox.pack_start c_hbox, true, false, 10
			hbox.pack_start @private, true, true, 10 
			
			frame_vbox.pack_start hbox, false, false, 0
			frame_vbox.pack_start @file_progress, false, false, 0
			frame_vbox.pack_start @total_progress, false, false, 0
			
			hbox = Gtk::HBox.new false, 10
			button = Gtk::Button.new("Exit")
			button.signal_connect("clicked") {
				save_prefs
				Gtk.main_quit
			}
			hbox.pack_start button
			
			@create_button.signal_connect("clicked") {
				
				@generator.announce = []
			
				if @announce.text and @announce.text.length > 1
					@generator.announce << [ @announce.text ]
				end
				
				@urls.each do |model, path, iter|
				
					next if path.depth > 1
				
					tier = []
					child = iter.first_child
					loop do
						tier << child[0]
						break unless child.next!
					end
					
					@generator.announce << tier
					
				end if @urls
				
				@generator.private = @private.active?
				@generator.chunk_size = ChunkSizes[@chunk_sizes.active] * 1024
				
				controls = [ 
					@private, @chunk_sizes, @announce , @create_button, @clear_button
				]
				
				controls.each{|c| c.sensitive = false}
				
				@generator.init
				
				@doit = false
				@selected = false
				@torrent_file = nil
				
				@dialog = Gtk::FileChooserDialog.new(
					"Select Where to save torrent",
					@window,
					Gtk::FileChooser::ACTION_SAVE,
					nil,
					[ Gtk::Stock::CANCEL, 	Gtk::Dialog::RESPONSE_CANCEL ],
					[ Gtk::Stock::SAVE, 		Gtk::Dialog::RESPONSE_ACCEPT ]
				)
				
				suggestion = GLib.filename_to_utf8(File.basename(@generator.dir))
				dir = @conf[:save_dir]
				@dialog.current_folder=dir unless dir.nil?
				@dialog.current_name="#{suggestion}.torrent"
				@dialog.do_overwrite_confirmation = true
				
				thr = Thread.new { 
					@generator.hash_file

					@msglabel.pop @context_id
					@generator.reset
					
					until @selected
						sleep 0.1
					end
					
					if @doit
						@generator.create_torrent
					end
					
					controls.each{|c| c.sensitive = true}
				}
				
				@doit = @dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
				if @doit
					@generator.file = @dialog.filename
					@conf[:save_folder] = File.dirname @generator.file
					@conf[:announce] = @generator.announce
					@conf[:private] = @private.active?
				else
					thr.kill
					@msglabel.pop @context_id
					@generator.reset
					controls.each{|c| c.sensitive = true}
				end
				@dialog.destroy
				@selected = true
			}

			@create_button.sensitive = false
			hbox.pack_start @create_button
			frame_vbox.pack_start hbox, false, false, 0
			
			frame.add frame_vbox
			vbox.pack_start frame, true, true, 0
			vbox.pack_start @msglabel, false, false, 0
			@window.add vbox
			
# re-enable this when scheduling and batch torrents are enabled
=begin
			@icon = Gtk::StatusIcon.new
			@icon.stock = Gtk::Stock::YES
			@icon.tooltip = Title
			
			@icon.signal_connect("activate") {
				unless @window.visible?
					@window.visible = true
				else
					if @window.active?
						@window.visible = false
					else
						@window.present
					end
				end
			}	
=end

			@window.show_all
			multi_announce.hide_all
			
		end
		def build_menu
			accel_group = Gtk::AccelGroup.new
			@window.add_accel_group accel_group
			
			item_factory = Gtk::ItemFactory.new(
				Gtk::ItemFactory::TYPE_MENU_BAR,
				'<main>',
				accel_group
			)

			items = [
				["/_File"],
				[
					'/_File/_New Torrent', 
					Gtk::ItemFactory::STOCK_ITEM, 
					"<control>N",
					Gtk::Stock::NEW,
					Proc.new{do_menu "new"}
				],
				[
					'/_File/_Quit', 
					Gtk::ItemFactory::STOCK_ITEM, 
					"<control>Q",
					Gtk::Stock::QUIT,
					Proc.new{do_menu "quit"}
				],
				["/_Help"],
				[
					"/_Help/_About", 
					Gtk::ItemFactory::STOCK_ITEM, 
					nil, 
					Gtk::Stock::ABOUT,
					Proc.new{do_menu "about"}
				]
			]

			item_factory.create_items items
			return item_factory.get_widget('<main>')
		end
		def do_menu(type)
			case type
			when "new" then
				@msglabel.pop @context_id
				@generator.clear
				@file_list.clear
				@folder_button.sensitive = true
				@files_button.sensitive = true
				@create_button.sensitive = false
				@announce.text=""
				@private.active=false
				@chunk_sizes.active=2
			when "quit" then
				Gtk.main_quit
			when "about" then
				puts "About"
			end
		end
		def accept_input?

			x=false
			@file_list.each{x=true;break}
			
			return false unless x
			
			x=false
			@urls.each{x=true;break} if @urls
			return x if @announce.text.nil? or @announce.text.length < 1
			return true
		end
		def pretty_size(size, decimals = true)
			
			pat = decimals ? "%.2f" : "%d"
			
			return "#{size.to_i} B" if size < 1024
			return sprintf("#{pat} kB", size.to_f / 1024) if size < 1048576
			return sprintf("#{pat} MB", size.to_f / 1048576) if size < 1073741824
			return sprintf("#{pat} GB", size.to_f / 1073741824) if size < 1099511627776
			return sprintf("#{pat} TB", size.to_f / 1099511627776)
		end
		def file_add_dialog(type_flag, multiple, title = "Select Files")
			dialog = Gtk::FileChooserDialog.new(
				title,
				@window,
				type_flag,
				nil,
				[ Gtk::Stock::CANCEL, 	Gtk::Dialog::RESPONSE_CANCEL ],
				[ Gtk::Stock::OPEN, 		Gtk::Dialog::RESPONSE_ACCEPT ]
			)
			dialog.select_multiple = multiple
			
			dir = @conf[:folder]
			dialog.current_folder = dir unless dir.nil?
			
			if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
				files = dialog.filenames
				if files.length > 1
					@conf[:folder] = @generator.dir = File.dirname(files[0])
					@generator.message "Suggested folder name will be \"#{File.basename @generator.dir}\""
				else
					@generator.dir = files[0]
					@conf[:folder] = File.dirname @generator.dir
					@generator.message "Suggested file name will be \"#{File.basename @generator.dir}\""
				end
				files.sort!{|a,b| a<=>b}
				files.each do |f|
					@generator.list_files f
				end
				
				@generator.files.each do |f|
					iter = @file_list.append
					iter[0] = GLib.filename_to_utf8(f[:path].join("/"))
					iter[1] = pretty_size(f[:length].to_f)
				end
				
				if @generator.files.length > 0
					@folder_button.sensitive = false
					@files_button.sensitive = false
				end
				
				@create_button.sensitive = accept_input?
			end
			
			dialog.destroy
		end
		def load_prefs
			path = File.expand_path ConfigFile
			unless File.exists? path
				@conf = Hash.new
			end
			begin
				@conf = YAML.load_file path
			rescue
				puts "Error reading #{path}: #{$!}"
				@conf = Hash.new
			end
			return @conf
		end
		def save_prefs
			path = File.expand_path ConfigFile
			begin
				File.open(path, 'w'){|f| YAML.dump(@conf, f)}
			rescue
				puts "Could not save configuration to #{path}: #{$!}"
			end
		end
		def create_announce_box(vbox)
			
			hbox = Gtk::HBox.new false, 10
			add_as_tier = Gtk::Button.new("Add")
			add_as_item = Gtk::Button.new("Add to group")
			remove = Gtk::Button.new("Remove")
			clear = Gtk::Button.new("Clear")
			
			add_as_item.sensitive = false
			remove.sensitive = false
			clear.sensitive = false
			
			hbox.pack_start add_as_tier, true, false, 0
			hbox.pack_start add_as_item, true, false, 0
			hbox.pack_start remove, true, false, 0
			hbox.pack_start clear, true, false, 0
			
			@urls = Gtk::TreeStore.new(String)
			list = Gtk::TreeView.new(@urls)
			list.height_request = 150
			list.selection.mode = Gtk::SELECTION_MULTIPLE
			
			renderer = Gtk::CellRendererText.new
			col = Gtk::TreeViewColumn.new("URL", renderer, :text => 0)
			col.resizable=true
			col.min_width=500
			list.append_column(col)
			
			tiers = @conf[:announce]
			if tiers and tiers.kind_of? Array
				tiers.each do |tier|
				
					@i ||= 0
					@i += 1
				
					iter = @urls.append(nil)
					iter[0] = "Tracker Group #{@i}"
					
					tier.each do |tracker|
						url = @urls.append(iter)
						url[0] = tracker
					end
				end unless tiers.flatten.length < 2
				list.expand_all
			end
			
			add_as_tier.signal_connect("clicked") {
			
				return if @announce.text == ""
				
				@i ||= 0
				@i += 1
				
				iter = @urls.append(nil)
				iter[0] = "Tracker Group #{@i}"
				
				iter = @urls.append(iter)
				iter[0] = @announce.text
				
				@announce.text = ""
				
				list.expand_all
				remove.sensitive = true
				add_as_item.sensitive = true
				clear.sensitive = true
			}
			
			add_as_item.signal_connect("clicked") {
			
				return if @announce.text == ""
			
				iter = nil
				list.selection.selected_each do |model, path, an_iter|
					iter = an_iter
# we can't break here or else ruby/gtk segfaults :/
				end
				
				return unless iter
				
				iter = iter.parent if iter.parent
				iter = @urls.append(iter)
				iter[0] = @announce.text
				
				list.expand_all
				
				@announce.text = ""
			}
			
			remove.signal_connect("clicked") {
				arr = []
				list.selection.selected_each do |model, path, iter|
					arr << Gtk::TreeRowReference.new(model, path)
				end
				
				arr.each do |ref|
					path = ref.path
					iter = @urls.get_iter(path)
					parent = iter.parent
					if parent and parent.n_children == 1
						@urls.remove parent
					else
						@urls.remove iter
					end
				end
				
				disable = true
				@urls.each{disable=false;break}
				if disable
					add_as_item.sensitive = false
					remove.sensitive = false
					clear.sensitive = false
				end
			}
			
			clear.signal_connect("clicked") {
				@urls.clear
				add_as_item.sensitive = false
				remove.sensitive = false
				clear.sensitive = false
			}
			
			label = Gtk::Label.new
			label.markup = "<small>Only add multiple URLs to a tracker group if they are on the SAME tracker!</small>"
			label.set_alignment(0.5, 0)
			vbox.add label
			vbox.add Gtk::ScrolledWindow.new.add(list)
			vbox.add hbox
			
		end
	end
end

if __FILE__ == $0
	Gtk.init
	Torrent::GtkMain.new
	Gtk.main
end
