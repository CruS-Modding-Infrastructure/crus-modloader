extends Node

var MODLOADER_VERSION = "0.2.1"
var MODS = []
var MOD_INFO = {}

var init_scripts = {}
var mod_dep_names = {} # mod name => names of mods that depend on them
var loads = 0
var inits = 0
var quit_game = false

class ModNode extends Node:
	var author: String
	var version: String
	var description: String
	var dependencies: Array
	var data = {}
	var packs = []
	var modpath: String
	var priority: float
	var loaded = false
	var initialized = false
	func _init(info: Dictionary):
		self.name = info["name"]
		self.author = info["author"]
		self.version = info["version"]
		self.description = info["description"]
		self.dependencies = info["dependencies"] if "dependencies" in info else []
		self.packs = info["packs"]
		self.modpath = info["modpath"]
		self.priority = float(info["priority"]) if "priority" in info else -1
	
func load_mod_json(path):
	var json = File.new()
	var res = {"error": "Failed to open mod.json"}
	if json.open(path, File.READ) == OK:
		var mod = JSON.parse(json.get_as_text())
		var errors = check_mod_json(mod.result)
		if mod.error != OK:
			match mod.error:
				ERR_PARSE_ERROR: res.error = "Couldn't parse line " + mod.error_line + " of mod.json"
				_: res.error = "Error " + mod.error + ": " + mod.error_string + " (line " + mod.error_line + ")"
		elif !(mod.result is Dictionary):
			res.error = "JSON is not an object (not enclosed in {}) in mod.json"
		elif len(errors) > 0:
			res.error = "Invalid JSON"
			res.error_list = errors
		else:
			res = mod.result
		json.close()
	return res

func check_mod_json(m: Dictionary) -> Array:
	var errs = []
	if !m.has_all(["name", "author", "version", "description"]):
		errs.append('Missing one or more of "name", "author", "version", "description" properties')
	if m.has("dependencies") and !(m["dependencies"] is Array):
		errs.append('Property "dependencies" must be an array of mod name strings')
	if m.has("dependencies") and m.name in m.dependencies:
		errs.append('Mod includes itself in its dependencies')
	if m.has("priority") and (!(m.priority is float) or m.priority < 0):
		errs.append('Property "priority" must be a number > 0')
	return errs

# Gets mod metadata from folder
func load_mod_info(path: String) -> Dictionary:
	mod_log("Scanning " + path, "Mod Loader")
	var dir = Directory.new()
	var mod_json = {"error": "Unknown JSON loading error"}
	var files = []
	var loaded_count = 0
	var json_found = false
	
	dir.open(path)
	dir.list_dir_begin(true, true)
	var fname = dir.get_next()
	while fname != "":
		var ext = fname.get_extension()
		if ext == "pck" or ext == "zip":
			files.append(dir.get_current_dir() + "/" + fname)
		elif fname == "mod.json":
			json_found = true
			mod_json = load_mod_json(dir.get_current_dir() + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	
	if !json_found:
		mod_json = {"error": "No mod.json found"}
	if !mod_json.has("error"):
		var init_path = mod_json.get("init")
		if init_path:
			init_scripts[mod_json["name"]] = init_path
		mod_json["packs"] = files
		mod_json["modpath"] = path.replace("user://mods", "res://MOD_CONTENT")
	
	return mod_json

# Loads mod data packs i.e. zip/pck files into the game
func load_mod_data(mod: ModNode):
	var bad_packs = []
	for p in mod.packs:
		var loaded = ProjectSettings.load_resource_pack(p)
		if loaded:
			mod_log("...loaded " + p, "Mod Loader")
		else: 
			mod_log("...failed to load " + p, "Mod Loader")
			bad_packs.append(p)
	if bad_packs.empty():
		mod.loaded = true
	return bad_packs

# Prepares metadata of mods in user://mods before loading actual data
func init_mods() -> Array:
	var mods = []
	var dir = Directory.new()
	var logfile = File.new()
	
	if dir.open('user://') == OK:
		if !dir.dir_exists('user://mods'):
			dir.make_dir('user://mods')
		else:
			if !dir.dir_exists('user://logs'):
				dir.make_dir('user://logs')
			if logfile.open("user://logs/mods.log", File.WRITE) == OK:
				logfile.store_line("-- CRUELTY SQUAD MOD LOADER v. " + MODLOADER_VERSION + " --\n")
				if OS.is_debug_build():
					logfile.store_line("WARNING: Game is in debug mode, if it's running via the editor directory calls will be broken if anything actually gets loaded (see https://github.com/godotengine/godot/issues/19815)\n")
				logfile.close()
			mod_log("Scanning mods folder...", "Mod Loader")
			dir.change_dir('user://mods')
			dir.list_dir_begin(true, true)
			var fname = dir.get_next()
			while fname != "":
				if dir.current_is_dir():
					var cur_dir = dir.get_current_dir()
					var mod = load_mod_info(dir.get_current_dir() + "/" + fname)
					if mod.has("name"):
						mods.append(mod)
						MOD_INFO[mod["name"]] = mod
						if mod.has("dependencies"):
							for dep in mod["dependencies"]:
								if !mod_dep_names.has(dep):
									mod_dep_names[dep] = [mod["name"]]
								else:
									mod_dep_names[dep].append(mod["name"])
						mod_log('...found mod "' + mod["name"] + '" by "' + mod["author"] + '"', "Mod Loader")
					elif mod.has("error"):
						var err_list = mod.get("error_list") if "error_list" in mod else []
						mod_log("ERROR: " + mod.error, "Mod Loader")
						if !err_list.empty():
							for err in err_list:
								mod_log("\t-> " + err, "Mod Loader")
					else:
						mod_log("ERROR: Couldn't load mod for an unknown reason!", "Mod Loader")
				fname = dir.get_next()
			dir.list_dir_end()
	return sort_mods_list(mods)

func sort_mods_list(mods: Array):
	var mods_new = []
	var mods_tmp = []
	
	# Topological sort for putting dependencies first
	for mod in mods:
		sort_mod(mod, mods_new, mods_tmp)
	
	# Sort list again by priority
	# The lower the priority the earlier the mod loads down to 0, -1 means no priority
	# TODO: maybe further priority tiebreakers like mod size, mod name alphanumeric order
	var priorities = {}
	for mod in mods_new:
		if !(mod.name in priorities):
			priorities[mod.name] = float(mod.priority) if "priority" in mod else -1
		if mod.name in mod_dep_names:
			for m in mod_dep_names[mod.name]:
				if m in priorities:
					# bump priority if a mod is somehow prioritized after a mod that depends on it
					if priorities[m] >= 0 and priorities[m] < priorities[mod.name]:
						priorities[mod.name] = priorities[m]
	var priority_lists = {}
	for mod in mods_new:
		var pri = priorities[mod.name]
		mod.priority = pri
		if pri in priority_lists:
			priority_lists[pri].append(mod)
		else:
			priority_lists[pri] = [mod]
	
	var pri_arr = priority_lists.keys()
	pri_arr.sort()
	var mod_list = []
	for i in pri_arr:
		if i == -1:
			continue
		mod_list.append_array(priority_lists[i])
	if -1 in priority_lists:
		mod_list.append_array(priority_lists[-1])
	
	return mod_list

func sort_mod(mod: Dictionary, mods_new: Array, mods_tmp: Array):
	if mods_new.has(mod):
		return
	if mods_tmp.has(mod):
		OS.alert('Failed to start game because mod "' + mod.name + '" has a circular dependency. Ensure your mods don\'t have a chain of dependencies leading back to themselves.', 'CruS Mod Loader')
		mod_log('CRITICAL ERROR: "' + mod.name + '" has a circular dependency', "Mod Loader")
		quit_game = true
		return
	
	mods_tmp.append(mod)
	if mod_dep_names.get(mod["name"]):
		for m in mod_dep_names.get(mod["name"]):
			sort_mod(MOD_INFO[m], mods_new, mods_tmp)
	
	mods_tmp.remove(mods_tmp.find(mod))
	mods_new.push_front(mod)

func _init():
	var config = ConfigFile.new()
	var dir = Directory.new()
	var err = config.load("user://modloader.cfg")
	var dump_files = []
	var dump_fgd = false
	var dump_path = "user://"
	
	# dumping any given files before loading data packs messes res:// up (in-editor)
	if err == OK:
		dump_files = config.get_value("util", "dump_files", [])
		dump_fgd = config.get_value("util", "dump_fgd", false)
		dump_path = config.get_value("util", "dump_path", "user://")
	if dump_files.size() > 0:
		for f in dump_files:
			dump_file(f, dump_path)
	if dump_fgd:
		dump_file("res://addons/qodot/game-definitions/fgd/qodot_fgd.tres", "user://")
	
	MODS = init_mods()
	
	# check for missing dependencies
	var mod_names = []
	for m in MODS:
		mod_names.append(m.name)
	var missing_dep_names = []
	for key in mod_dep_names.keys():
		if !(key in mod_names):
			missing_dep_names.append(key)
	if !missing_dep_names.empty():
		var msg = "Failed to start game because mod dependencies are missing.\n\nMissing mods:"
		for m in missing_dep_names:
			msg += "\n- " + m
		OS.alert(msg, 'CruS Mod Loader')
		mod_log("CRITICAL ERROR: missing mod dependencies", "Mod Loader")
		mod_log("Missing mods:", "Mod Loader")
		for m in missing_dep_names:
			mod_log("- " + m + " (required by: " + str(mod_dep_names[m]) + ")", "Mod Loader")
		quit_game = true

	if !quit_game:
		# load data packs and prepare init scripts
		mod_log("Finished scanning for mods, loading mod data...", "Mod Loader")
		for mod in MODS:
			mod_log("...loading \"" + mod["name"] + str('" (', loads + 1, "/", MODS.size(), ")"), "Mod Loader")
			var n = ModNode.new(mod)
			var bad_files = load_mod_data(n)
			if mod["name"] in init_scripts.keys():
				var init_path = init_scripts[mod["name"]]
				if init_path and ResourceLoader.exists(init_path):
					var scr = ResourceLoader.load(init_path)
					if scr:
						init_scripts[mod["name"]] = scr
						mod_log("...init script at " + init_path, "Mod Loader")
					else:
						mod = {"error": "Init script failed to load"}
			else:
				n.initialized = true
			if bad_files.empty() and !mod.has("error"):
				add_child(n)
				loads += 1
			elif bad_files.size > 0:
				OS.alert('Failed to start game because mod "' + mod.name + '" couldn\'t fully load. Check %appdata%\\Godot\\app_userdata\\Cruelty Squad\\logs\\mods.log for more information.', 'CruS Mod Loader')
				mod_log('CRITICAL ERROR: "' + mod.name + '" failed to load the following files:', "Mod Loader")
				for bf in bad_files:
					mod_log('	- ' + bf, "Mod Loader")
				quit_game = true
				return
			elif mod.has("error"):
				OS.alert('Failed to start game because mod "' + mod.name + '" couldn\'t fully load. Check %appdata%\\Godot\\app_userdata\\Cruelty Squad\\logs\\mods.log for more information.', 'CruS Mod Loader')
				mod_log('CRITICAL ERROR: couldn\'t load the init script for "' + mod.name + '".', "Mod Loader")
				quit_game = true
				return

func _enter_tree():
	if quit_game:
		get_tree().quit()

func _ready():
	if !quit_game:
		# init and add mods to the scene tree under Mod
		mod_log("Finished loading data packs, running init scripts...", "Mod Loader")
		for mod in init_scripts.keys():
			var scr = init_scripts[mod]
			var mod_node = get_node(mod)
			var inst = Node.new()
			inst.name = "Init"
			mod_node.add_child(inst)
			mod_log('...initializing "' + mod + str('" (', inits + 1, "/", init_scripts.keys().size(), ")"), "Mod Loader")
			inst.set_script(scr)
			inits += 1
		mod_log("MOD LOADING COMPLETE: Successfully loaded " + str(loads) + " mod(s)", "Mod Loader")

# Utility functions

func mod_log(s: String, mod):
	var logfile = File.new()
	var dir = Directory.new()
	var dt = OS.get_datetime()
	var dt_str = "%02d:%02d:%02d - " % [dt.hour, dt.minute, dt.second]
	var n = ""
	if mod:
		if mod is Object:
			n = mod.name if "name" in mod else mod.MOD_NAME
		elif mod is String:
			n = mod
	assert(n != "", "ERROR: mod_log called without a string or Object parameter")
	if !dir.dir_exists('user://logs'):
		dir.make_dir('user://logs')
	if logfile.open("user://logs/mods.log", File.READ_WRITE) == OK:
		logfile.seek_end()
		logfile.store_line(dt_str + "[" + n + "] " + s)
		logfile.close()
	print(dt_str + "[" + n + "] " + s)

func dump_file(filepath: String, outpath="user://dump", preserve_folder_structure=false):
	filepath = filepath.trim_suffix(".import")
	var ext = filepath.get_extension()
	var dirpath = ""
	if ResourceLoader.exists(filepath):
		if preserve_folder_structure:
			var dir := Directory.new()
			dirpath = filepath.replace("res://", "user://")
			dirpath = filepath.substr(0, filepath.length() - filepath.get_file().length())
			if !dir.dir_exists(dirpath):
				dir.make_dir_recursive(dirpath)
		var obj = ResourceLoader.load(filepath)
		match ext:
			"png":
				obj.get_data().save_png(outpath + "/" + dirpath.trim_prefix("res://") + filepath.get_file())
			_:
				ResourceSaver.save(outpath + "/" + dirpath.trim_prefix("res://") + filepath.get_file(), obj)

func dump_folder(dirpath: String, outpath="user://"):
	var dir = Directory.new()
	var outdir = outpath + "/" + dirpath.replace("res://", "")
	if dir.open(dirpath) == OK:
		mod_log("Dumping contents of " + dirpath + " to " + outpath, "Mod Loader")
		if !dir.dir_exists(outdir):
			dir.make_dir_recursive(outdir)
		dir.list_dir_begin(true, true)
		var fname = dir.get_next()
		while fname != "":
			if dir.current_is_dir():
				dump_folder(dirpath + "/" + fname, outpath)
			else:
				dump_file(dirpath + "/" + fname, outpath, true)
			fname = dir.get_next()
		dir.list_dir_end()
	else:
		mod_log("Failed to dump " + dirpath, "Mod Loader")
