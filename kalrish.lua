local string_match = string.match
local package_searchpath = package.searchpath
local texconfig = texconfig
local texio_write = texio.write
local texio_write_nl = texio.write_nl

local lua_module_loading = 1
local own_reporting = true
local data_processing = false
local own_file_discovery = false
local max_display_node_trees = 2
local pk_mode = "localfont"

local open_com = function(target)
	texio_write_nl(target, "luais-kalrish: ")
end

do
	local switches = {
		["debug-lua-globals"] = function(v)
			if v then
				local rawset = rawset
				local tostring = tostring
				local type = type
				
				setmetatable(_G,
					{
						__newindex = function(t, k, v)
							texio_write_nl("term and log", "Lua globals debugger: global written")
							texio_write_nl("term and log", "\tkey: ")
							texio_write("term and log", k)
							texio_write_nl("term and log", "\ttype: ")
							texio_write("term and log", type(v))
							texio_write_nl("term and log", "\tvalue: ")
							texio_write("term and log", tostring(v))
							
							rawset(t, k, v)
						end
					}
				)
			end
		end,
		["own-reporting"] = function(v)
			own_reporting = v
		end,
		["data-processing"] = function(v)
			data_processing = v
		end,
		["own-file-discovery"] = function(v)
			own_file_discovery = v
		end,
		["limit-node-tree-display"] = function(v)
			if v then
				max_display_node_trees = nil
			end
		end
	}
	
	local get_texconfig_setter = function(s)
		return function(v)
			open_com("log")
			texio_write("log", "texconfig: setting ")
			texio_write("log", s, " to ", v)
			
			texconfig[s] = tonumber(v)
		end
	end
	
	local lua_module_loading_ways = {
		["default"] = 0,
		["bytecode-fallback"] = 1,
		["bytecode-only"] = 2
	}
	
	local options = {
		["lua-module-loading"] = function(v)
			lua_module_loading = lua_module_loading_ways[v]
		end,
		["max-display-node-trees"] = function(v)
			max_display_node_trees = tonumber(v)
		end,
		["pk-mode"] = function(v)
			pk_mode = v
		end,
		["string-vacancies"] = get_texconfig_setter("string_vacancies"),
		["max-strings"] = get_texconfig_setter("max_strings")
	}
	
	local arg = arg
	
	local i = 1
	local argument = arg[1]
	while argument do
		local switch, value = string_match(argument, "%-%-([^=]+)=(.+)")
		
		if not switch then
			switch, value = string_match(argument, "%-%-([^=]+)")
		end
		
		if switch then
			local found = switches[switch]
			if found then
				if value then
					if value == "yes" then
						value = true
					elseif value == "no" then
						value = false
					else
						open_com("term and log")
						texio_write("term and log", "command line: invalid argument for switch --")
						texio_write("term and log", switch, " ('", value, "')")
					end
				else
					value = true
				end
				
				found(value)
			else
				found = options[switch]
				if found then
					if value then
						found(value)
					else
						open_com("term and log")
						texio_write("term and log", "command line: missing argument for option --")
						texio_write("term and log", switch)
					end
				end
			end
		end
		
		i = i + 1
		argument = arg[i]
	end
end

local luatex_engine = status.luatex_engine
local directory_separator = string_match(package.config, "^[^\n]*")

do
	local bytecode_file_extension = ({
		["luatex"] = "texluabc",
		["luajittex"] = "texluajitbc"
	})[luatex_engine]
	
	--[[
	local engine_variable = ({
		["luatex"] = "LUATEX_PATH",
		["luajittex"] = "LUAJITTEX_PATH"
	})[luatex_engine]
	]]
	
	--package.path = [[?.]] .. bytecode_file_extension .. [[;]] .. ( os.getenv(engine_variable) or "" ) .. [[C:\Users\David\local\lib\]] .. luatex_engine .. [[\lua_modules\?.]] .. bytecode_file_extension
	
	--[[
	local package_searchers = package.searchers or package.loaders
	
	local standard_searcher = package_searchers[2]
	
	local loadfile = loadfile
	local string_gsub = string.gsub
	
	package_searchers[2] = function(module)
		local prefix, rest = string_match(module, "^([^.]+)%.(.+)$")
		if prefix then
			local dir = prefix2dir[prefix]
			if dir then
				local rv1, rv2 = loadfile(dir .. directory_separator .. string_gsub(rest, '%.', directory_separator) .. bytecode_file_extension, "b")
				if rv1 then
					return rv1
				end
			end
		end
		
		return standard_searcher(module)
	end
	]]
	
	local package_searchers = package.searchers or package.loaders
	
	local standard_searcher = package_searchers[2]
	
	local loadfile = loadfile
	
	local our_path
	if lua_module_loading == 1 or lua_module_loading == 2 then
		our_path = [[?.]] .. bytecode_file_extension .. [[;C:\Users\David\local\lib\]] .. luatex_engine .. [[\lua_modules\?.]] .. bytecode_file_extension
	else
		our_path = [[C:\Users\David\local\lib\]] .. luatex_engine .. [[\lua_modules\?.]] .. bytecode_file_extension
	end
	
	package_searchers[2] = function(module)
		local path, error_message = package_searchpath(module, our_path)
		if path then
			open_com("log")
			texio_write("log", "Lua module loader: module '", module, "' found in bytecode form")
			
			local rv1, rv2 = loadfile(path, "b")
			if rv1 then
				return rv1
			elseif lua_module_loading == 1 then
				open_com("log")
				texio_write("log", "Lua module loader: module '", module, "' could not be loaded in bytecode form: ", rv2)
				
				return standard_searcher(module)
			else
				return rv2
			end
		elseif lua_module_loading == 0 or lua_module_loading == 1 then
			open_com("log")
			texio_write("log", "Lua module loader: module '", module, "' not found in bytecode form")
			
			return standard_searcher(module)
		end
	end
end

do -- Callbacks
	local callback_register = callback.register
	
	if own_reporting then -- Information reporting callbacks
		local require = require
		
		--[[  This pre_dump callback doesn't replace any code,
		       i.e. we cannot get rid of that "Beginning to dump on..." message
		callback_register("pre_dump",
			function()
			end
		)
		]]
		callback_register("start_run",
			function()
				require("altlog.start_run")()
				
				callback_register("start_page_number", require("altlog.start_page_number"))
				callback_register("stop_page_number", require("altlog.stop_page_number"))
			end
		)
		callback_register("stop_run", require("altlog.stop_run"))
		callback_register("start_file", require("altlog.start_file"))
		callback_register("stop_file", require("altlog.stop_file"))
		--callback_register("show_error_message", require("altlog.show_error_message"))
		
		do
			local hpack_quality = require("altlog.hpack_quality")
			local vpack_quality = require("altlog.vpack_quality")
			
			local nodetree_analyze
			if max_display_node_trees then
				local nodetree = require("nodetree")
				
				nodetree.set_option("engine", "luatex")
				nodetree.set_default_options()
				
				nodetree_analyze = nodetree.analyze
			end
			
			local times = 0
			
			local analyze = function(incident, head)
				if incident == "overfull" or incident == "underfull" then
					if max_display_node_trees then
						if max_display_node_trees == 0 or times < max_display_node_trees then
							times = times + 1
							nodetree_analyze(head)
						end
					end
				end
			end
			
			callback_register("hpack_quality",
				function(incident, detail, head, first, last)
					hpack_quality(incident, detail, head, first, last)
					analyze(incident, head)
				end
			)
			callback_register("vpack_quality",
				function(incident, detail, head, first, last)
					vpack_quality(incident, detail, head, first, last)
					analyze(incident, head)
				end
			)
			
			--callback.register("pre_output_filter",
			--	function(head)
			--		nodetree.analyze(head)
			--	end
			--)
		end
	end
	
	if not data_processing then -- Data processing callbacks
		callback_register("process_input_buffer", false)
		callback_register("process_output_buffer", false)
		callback_register("process_jobname", false)
	end
	
	if own_file_discovery then -- File callbacks
		open_com("log")
		texio_write("log", "replacing file discovery")
		
		local io_open = io.open
		
		local kpathsea = kpse.new(luatex_engine)
		
		do -- File discovery callbacks
			callback_register("find_format_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_format_file looking for '")
					texio_write("log", name, "'")
					
					local fd = io_open(name, "rb")
					if fd then
						fd:close()
						
						return name
					else
						local path = [[C:\Users\David\local\lib\]] .. luatex_engine .. [[\formats\]] .. name
						fd = io_open(path, "rb")
						if fd then
							fd:close()
							
							return path
						end
					end
				end
			)
			
			callback_register("find_read_file",
				function(id, name)
					open_com("log")
					texio_write("log", "file discovery: find_read_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "tex")
				end
			)
			
			callback_register("find_write_file",
				function(id_number, name)
					return name
				end
			)
			
			callback_register("find_font_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_font_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "tfm", true)
				end
			)
			
			callback_register("find_vf_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_vf_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "vf")
				end
			)
			
			callback_register("find_map_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_map_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "map")
				end
			)
			
			callback_register("find_enc_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_enc_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "enc files")
				end
			)
			
			callback_register("find_sfd_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_sfd_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "subfont definition files")
				end
			)
			
			callback_register("find_pk_file",
				function(name, dpi)
					open_com("log")
					texio_write("log", "file discovery: find_pk_file looking for '")
					texio_write("log", name, "' at ", tostring(dpi), "dpi")
					
					local path = kpathsea:find_file(name, "pk", dpi)
					if path then
						return path
					else
						path = [[C:\Users\David\local\share\fonts\pk\]] .. pk_mode .. [[\]] .. dpi .. [[\]] .. name .. ".pk"
						local fd = io_open(path, "rb")
						if fd then
							fd:close()
							
							return path
						end
					end
				end
			)
			
			callback_register("find_data_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_data_file looking for '")
					texio_write("log", name, "'")
					
					return name
				end
			)
			
			callback_register("find_type1_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_type1_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "type1 fonts") or kpathsea:find_file(name, "opentype fonts")
				end
			)
			
			callback_register("find_truetype_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_truetype_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "truetype fonts")
				end
			)
			
			callback_register("find_opentype_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_opentype_file looking for '")
					texio_write("log", name, "'")
					
					return kpathsea:find_file(name, "truetype fonts") or kpathsea:find_file(name, "opentype fonts")
				end
			)
			
			callback_register("find_image_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_image_file looking for '")
					texio_write("log", name, "'")
					
					return name
				end
			)
			
			callback_register("find_output_file",
				function(name)
					open_com("log")
					texio_write("log", "file discovery: find_output_file looking for '")
					texio_write("log", name, "'")
					
					return name
				end
			)
		end
		
		do -- File reading callbacks
			local string_find = string.find
			
			callback_register("open_read_file",
				function(path)
					local fd = io_open(path, "rb")
					if fd then
						local contents = fd:read("*a")
						
						fd:close()
						
						if contents then
							local step = 1
							return {
								reader = function(t)
									local start, stop, next_line = string_find(contents, "([^\n]+)", step)
									if start then
										step = stop + 1
									end
									return next_line
								end
							}
						end
					end
					
					--[[
					return {
						reader = function()
							return ""
						end
					}
					]]
				end
			)
			
			do
				local string_len = string.len
				
				local reader = function(path)
					local fd = io_open(path, "rb")
					if fd then
						local contents = fd:read("*a")
						
						fd:close()
						
						if contents then
							return true, contents, string_len(contents)
						else
							return false, "", 0
						end
					else
						return false, "", 0
					end
				end
				
				callback_register("read_font_file", reader)
				callback_register("read_vf_file", reader)
				callback_register("read_map_file", reader)
				callback_register("read_enc_file", reader)
				callback_register("read_sfd_file", reader)
				callback_register("read_pk_file", reader)
				callback_register("read_data_file", reader)
				callback_register("read_type1_file", reader)
				callback_register("read_truetype_file", reader)
				callback_register("read_opentype_file", reader)
			end
		end
		
		texconfig.kpse_init = false
	end
end

texconfig.error_line = 254
texconfig.half_error_line = 238
texconfig.max_print_line = 65535