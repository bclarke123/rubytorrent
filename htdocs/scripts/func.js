/*

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

*/

function $(el) { return document.getElementById(el); }
function ce(el) { return document.createElement(el); }
function ct(t) { return document.createTextNode(t); }

function toggleSidebar() {
	var sidebar=$('files');
	var cName = (sidebar.className=='closed') ? '' : 'closed';
	sidebar.className=cName;
	$('content').className=cName;
}

function xh() {
	try { 
		return new XMLHttpRequest(); 
	} catch(e1) {
		try {
			return new ActiveXObject("Msxml2.XMLHTTP");
		} catch(e2) {
			try {
				return new ActiveXObject("Microsoft.XMLHTTP");
			} catch(e3) {
				return null;
			}
		}
	}
}

function FileTree(dir, req, type) {
	this.dir = dir;
	this.transport = req ? req : xh();
	this.type = type ? type : FileTree.TYPE_DIR;
	this.init();
}

FileTree.STATE_CLOSED=1;
FileTree.STATE_OPEN=2;
FileTree.STATE_LOADING=3;
FileTree.TYPE_FILE=1;
FileTree.TYPE_DIR=2;

FileTree.selected = [];

FileTree.THROBBER="/images/throbber.gif";
FileTree.FILE="/images/file.png";
FileTree.DIR="/images/folder.png";
FileTree.DIR_OPEN="/images/folderopen.png";
FileTree.MINUS="/images/minus.gif";
FileTree.PLUS="/images/plus.gif";
FileTree.BLANK="/images/blank.gif";
FileTree.CLASS_NORMAL="treeNode";
FileTree.CLASS_SELECTED="treeNodeSel";

FileTree.prototype={
	outer: null,
	target: null,
	icon: null,
	pmIcon: null,
	transport: null,
	state: FileTree.STATE_CLOSED,
	type: null,
	dir: null,
	children: null,
	parent: null,
	init:function() {
		var nobr = ce("nobr");
		this.icon = ce("img");
		var span = ce("span");
		var pm = ce("img");
		var _this = this;

		if(this.type == FileTree.TYPE_DIR) {
			pm.src=FileTree.PLUS;
			pm.style.cursor="pointer";
			this.icon.style.cursor="pointer";
			this.pmIcon = pm;
			this.icon.src = FileTree.DIR;
			pm.onclick=function() { _this.toggle.call(_this); }
		} else {
			pm.src=FileTree.BLANK;
			this.icon.src = FileTree.FILE;
		}
		
		this.icon.onclick = span.onclick=function(event) {
			_this.select.call(_this, event);
		}
		
		span.appendChild(ct(this.dir));
		
		nobr.appendChild(pm);
		nobr.appendChild(this.icon);
		nobr.appendChild(span);
		
		this.outer = ce("div");
		this.outer.className = FileTree.CLASS_NORMAL;
		this.outer.appendChild(nobr);
		
		if(this.type == FileTree.TYPE_DIR) {
			this.target = ce("div");
			this.target.style.display = "none";
			this.outer.appendChild(this.target);
		}
	},
	bind:function(parent) {
		this.parent = parent;
		if(this.parent != null) {
			this.parent.target.appendChild(this.outer);
		}
	},
	expand:function() {
		
		if(this.children == null) {
			
			this.icon.src = FileTree.THROBBER;
			this.state = FileTree.STATE_LOADING;
			
			var dir = escape(this.directory());
			var _this = this;
			
			this.transport.open("GET", "/dir_list?dir=" + dir, true);
			this.transport.onreadystatechange=function(){
				if(_this.transport.readyState == 4) { _this.doLoad.call(_this); }
			}
			this.transport.send(null);
		} else {
			this.show();
			this.icon.src = FileTree.DIR_OPEN;
			this.pmIcon.src = FileTree.MINUS;
			this.state = FileTree.STATE_OPEN;
		}
	},
	contract:function() {
			this.hide();
			this.icon.src = FileTree.DIR;
			this.pmIcon.src = FileTree.PLUS;
			this.state = FileTree.STATE_CLOSED;
	},
	toggle:function() {
		if(this.state == FileTree.STATE_OPEN) {
			this.contract();
		} else 
		if(this.state != FileTree.LOADING) {
			this.expand();
		}
	},
	doLoad:function() {
		var doc = this.transport.responseXML;
		if(!doc) { return; }
		
		doc = doc.documentElement;
		var dirs = doc.getElementsByTagName("dir");
		
		this.children = [];
		var x=0, dir, child;
		
		for(var i=0; i<dirs.length; i++) {
			dir = dirs[i].firstChild.nodeValue;
			child = new FileTree(dir, this.transport, FileTree.TYPE_DIR);
			child.bind(this);
			this.children[x] = child;
			x++;
		}
		
		dirs = doc.getElementsByTagName("file");
		
		for(var i=0; i<dirs.length; i++) {
			dir = dirs[i].firstChild.nodeValue;
			child = new FileTree(dir, this.transport, FileTree.TYPE_FILE);
			child.bind(this);
			this.children[x] = child;
			x++;
		}
		
		this.transport = null;
		this.expand();
	},
	show:function() {
		this.target.style.display='block';
	},
	hide:function() {
		this.target.style.display='none';
	},
	isSibling:function(el) {
		return el.parent == this.parent;
	},
	isAncestor:function(el) {
		return el.isDescendant(this);
	},
	isDescendant:function(el) {
		var parent = this.parent;
		while(parent) {
			if(parent == el) { return true; }
			parent = parent.parent;
		}
	},
	directory:function() {
		var dir = this.dir;
		var parent = this.parent;

		while(parent) {
			if(parent.dir != '/') {
				dir = parent.dir + '/' + dir;
			} else {
				dir = '/' + dir;
			}
			parent = parent.parent;
		}
		return dir;
	},
	select:function(event) {

		event.cancelBubble = true;
		this.outer.className = FileTree.CLASS_SELECTED;
		var arr = FileTree.selected;
		
		if(arr.length == 0) {
			FileTree.selected[0] = this;
			return;
		}

		var newSel = [];
		
		if(event.shiftKey) {
			var last = arr[arr.length - 1];
			if(this.isSibling(last)) {
				var siblings = this.parent.children;
				var sibIdx = -1, myIdx = -1, sibling;
				for(var i=0; i<siblings.length; i++) {
					sibling = siblings[i];
					if(this == sibling) { myIdx = i; }
					if(last == sibling) { sibIdx = i; }
					if(myIdx > -1 && sibIdx > -1) { break; }
				}
				
				var min = Math.min(sibIdx, myIdx);
				var max = Math.max(sibIdx, myIdx) + 1;
				
				for(var i=min; i<max; i++) {
					var next = siblings[i];
					if(next != last) { // already there
						next.outer.className = FileTree.CLASS_SELECTED;
						arr.push(next);
					}
				}

			} else {
				for(var i=0; i<arr.length; i++) {
					arr[i].outer.className = FileTree.CLASS_NORMAL;
				}
				if(arr.length == 1 && arr[0] == this) {
					FileTree.selected = [];
				} else {
					this.outer.className = FileTree.CLASS_SELECTED;
					FileTree.selected = [ this ];
				}
			}
		} else
		if(event.ctrlKey) {
			for(var i=0; i<arr.length; i++) {
				var sel = arr[i];
				if(sel == this) {
/* sort to put this last, then pop it off the end */
					arr.sort(function(a,b){return(a==sel)?1:((b==sel)?-1:0);});
					arr[arr.length - 1].outer.className = FileTree.CLASS_NORMAL;
					arr.pop();
					FileTree.selected = arr;
					return;
				} else
				if(this.isSibling(sel)) {
					newSel.push(sel);
				} else {
					sel.outer.className = FileTree.CLASS_NORMAL;
				}
			}
			newSel.push(this);
			FileTree.selected = newSel;
		} else {
			for(var i=0; i<arr.length; i++) {
				arr[i].outer.className = FileTree.CLASS_NORMAL;
			}
			if(arr.length == 1 && arr[0] == this) {
				FileTree.selected = [];
			} else {
				this.outer.className = FileTree.CLASS_SELECTED;
				FileTree.selected = [ this ];
			}
		}
		return false;
	}
};

function addTracker() {
	var url = $('url').value;
	if(url == null || url.length == 0) {
		alert("Please enter a tracker URL to add.");
		return;
	}
	
	var trackers = $('trackers');
	trackers.options[trackers.options.length] = new Option(url, url, false, false);
	$('url').value = "";
}

function delTracker() {
	var trackers = $('trackers');
	while(trackers.selectedIndex > -1) {
		trackers.remove(trackers.selectedIndex);
	}
}

function doFormSubmit() {
	
	$('mainThrobber').src = FileTree.THROBBER;
	
	announceText = $('url');
	announceList = $('trackers');
	
	if(FileTree.selected.length == 0) {
		alert("Please select one or more files from the tree on the left");
		return false;
	}
	
	if(announceText.value == "" && announceList.options.length == 0) {
		alert("Please specify one or more tracker announce URLs.");
		return false;
	}
	
	var files = "";
	for(var i=0; i<FileTree.selected.length; i++) {
		files += FileTree.selected[i].directory();
		if(i < FileTree.selected.length - 1) { files += ";"; }
	}
	
	var trackers = announceText.value;
	for(var i=0; i<announceList.options.length; i++) {
		if(trackers.length > 0) {
			trackers += ";";
		}
		trackers += announceList.options[i].value;
	}
	
	var chunkSize = $('csize').options[$('csize').selectedIndex].value;
	
	var postBody = 
		"files=" + escape(files) + 
		"&trackers=" + escape(trackers) +
		"&csize=" + escape(chunkSize) +
		"&private=" + escape($('private').checked ? "on" : "off") +
		"&local=" + escape($('local').checked ? "on" : "off");
		
	var request = xh();
	request.open("POST", "/create_torrent", true);
	request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
	request.onreadystatechange=function(){if(request.readyState==4){formUpdate(request);}};
	request.send(postBody);
	
	return false;
}

function formUpdate(request) {
	var doc = request.responseXML;
	
	if(!doc) { 
		alert(request.responseText);
		return;
	}
	
	var root = doc.documentElement;
	
	switch(root.nodeName) {
		case "update": parseUpdate(root, request); break;
		case "error": handleError(root); break;
		case "done": handleFinished(root); break;
		default: alert(request.responseText);
	}
}

function parseUpdate(root, request) {
	var filePct = parseFloat(root.getAttribute('file'));
	var totalPct = parseFloat(root.getAttribute('total'));
	var currFile = root.firstChild;
	if(currFile) { currFile = currFile.nodeValue; }
	
	if(!(isNaN(filePct) || isNaN(totalPct))) {
		$('fprog').style.width = (filePct * 100) + "%";
		$('tprog').style.width = (totalPct * 100) + "%";
		$('currFile').innerHTML = currFile;
	}
	
	setTimeout(
		function() {
			request.open("GET", "/create_torrent", true);
			request.onreadystatechange=function(){
				if(request.readyState==4){formUpdate(request);}
			};
			request.send(null);
		},
		1000
	)
}

function handleError(root) { 
	alert("Error: " + root.firstChild.nodeValue);
	$('mainThrobber').src = FileTree.BLANK;
}

function handleFinished(root) {
	$('mainThrobber').src = FileTree.BLANK;
	$('fprog').style.width = "0%";
	$('tprog').style.width = "0%";
	$('currFile').innerHTML = "--";
	window.location='/create_torrent?dl=1';
}

document.onmousedown=function(e){if(e.shiftKey){return false;}};
window.onload=function() {
	var fileList = new FileTree('/');
	$('fileContent').appendChild(fileList.outer);
	fileList.expand();
}
