extends Steam

var MODLOADER_VERSION = "0.0.1 (CRAPPY INITIAL RELEASE)"
var MODS = {}

func mod_log(s: String):
	var logfile = File.new()
	var dir = Directory.new()
	if !dir.dir_exists('user://logs'):
		dir.make_dir('user://logs')
	if logfile.open("user://logs/mods.log", File.READ_WRITE) == OK:
		print(s)
		logfile.seek_end()
		logfile.store_line(s)
		logfile.close()
	
func is_valid_mod_json(m: Dictionary) -> bool:
	return m.has_all(["name", "author", "version", "description"])

func load_mod(path: String) -> Dictionary:
	mod_log("[Mod Loader] Scanning " + path)
	var dir = Directory.new()
	var mod = {}
	var files = []
	var loaded_count = 0
	var json_valid = false
	dir.open(path)
	dir.list_dir_begin(true, true)
	var fname = dir.get_next()
	while fname != "":
		var ext = fname.get_extension()
		if ext == "pck" or ext == "zip":
			files.append(dir.get_current_dir() + "/" + fname)
		elif fname == "mod.json":
			var json = File.new()
			if json.open(dir.get_current_dir() + "/" + fname, File.READ) == OK:
				mod = JSON.parse(json.get_as_text())
				if mod.error == OK and mod.result is Dictionary and is_valid_mod_json(mod.result):
					json_valid = true
				elif mod.error != OK:
					match mod.error:
						ERR_PARSE_ERROR: mod_log("[Mod Loader] ERROR: Problem on line " + mod.error_line + " of mod.json in " + path)
						_: mod_log("[Mod Loader] ERROR: Unspecified, code " + mod.error)
				elif !(mod.result is Dictionary):
					mod_log("[Mod Loader] ERROR: JSON is not an object (not enclosed in {}) for mod.json in " + path)
				elif !is_valid_mod_json(mod.result):
					mod_log("[Mod Loader] ERROR: Missing name, author, version and/or description for mod.json in " + path)
		fname = dir.get_next()
	if json_valid:
		for f in files:
			var loaded = ProjectSettings.load_resource_pack(f)
			if loaded:
				mod_log("...loaded " + f)
				loaded_count += 1
			else: mod_log("...failed to load " + f)
	if loaded_count == 0:
		mod_log("[Mod Loader] ERROR: No mod files found!")
	return mod.result if loaded_count > 0 else {}

func initMods() -> Array:
	# TODO: generate and respect load order cfg
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
				logfile.close()
			dir.change_dir('user://mods')
			dir.list_dir_begin(true, true)
			var fname = dir.get_next()
			while fname != "":
				if dir.current_is_dir():
					dir.change_dir(fname)
					var cur_dir = dir.get_current_dir()
					var mod = load_mod(cur_dir)
					if mod.has("name"):
						mods.append(mod)
						mod_log("[Mod Loader] Finished loading mod " + mod["name"] + " by " + mod["author"])
				fname = dir.get_next()
	return mods
					

func _init():
	MODS = initMods()
	mod_log("[Mod Loader] ALL MOD LOADING COMPLETE: successfully loaded " + str(MODS.size()) + " mod(s)")
	steamInit()

func _ready():
	pass
