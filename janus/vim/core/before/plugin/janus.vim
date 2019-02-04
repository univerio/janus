""
"" Janus main functions
""

" Return a path separator on the current OS
" Taken from pathogen
"
" @return [String] The separator / or \
function! janus#separator()
  return !exists("+shellslash") || &shellslash ? '/' : '\'
endfunction

" Return the expanded path
"
" @param [String] path
" @return [String] Absolute path
function! janus#expand_path(path)
  return expand(a:path)
endfunction

" Return a resolved path
"
" @param [String] path
" @return resolved path
function! janus#resolve_path(path)
  return resolve(janus#expand_path(a:path))
endfunction

" Find vim files inside a folder
"
" @param [String] The path to a folder
" @return [List] List of files.
function! janus#vim_files(folder)
  let files = []
  let pattern = janus#resolve_path(a:folder) . janus#separator() . "*"
  " Add all found vim files
  for file in split(glob(pattern), "\n")
    if isdirectory(file)
      call extend(files, janus#vim_files(file))
    elseif (file =~ "\.vim$")
      call add(files, file)
    endif
  endfor

  return files
endfunction

function! s:new_plugin(group, plug_args)
  return {"group": a:group, "args": a:plug_args}
endfunction

function! s:add_pending_plugin(type, group, plug_args)
  if !exists("s:pending_plugins")
    let s:pending_plugins = {}
  endif
  if !has_key(s:pending_plugins, a:type)
    let s:pending_plugins[a:type] = []
  endif
  let plug = s:new_plugin(a:group, a:plug_args)
  call add(s:pending_plugins[a:type], plug)
  return plug
endfunction

" Add a group of plug-ins to plug
"
" @param [String] The group name
" @param [List] List of (<path>) | (<name>, [<repo>, [opts]]) tuples
function! janus#add_group(name, plugs)
  let type = a:name == "core" ? "core" : "bundled"

  " Add plugins
  for plug in a:plugs
    let [plug_name; plug_args] = plug
    if len(plug_args) > 0 " bundled plugin
      let [repo; opts] = plug_args
      if len(opts) > 0
        let [opts] = opts
      else
        let opts = {}
      endif
      call extend(opts, {"as": plug_name, "dir": janus#plugin_path(plug_name)})
      let plug = s:add_pending_plugin(type, a:name, [repo, opts])
      if !exists("s:bundled_plugins")
        let s:bundled_plugins = {}
      endif
      let s:bundled_plugins[plug_name] = plug
    else " janus-internal plugin
      let plug_path = g:janus_vim_path . janus#separator() . a:name . janus#separator() . plug_name
      call s:add_pending_plugin(type, a:name, [plug_path, {"as": a:name . "#" . plug_name}])
    endif
  endfor
endfunction

function! s:get_legacy_custom_plugins(path)
  let plugins = []
  for dir in split(globpath(a:path, "*"), "\n")
    if !isdirectory(dir)
      continue
    endif
    let plug = s:new_plugin("custom", [dir, {"as": fnamemodify(dir, ":t")}])
    call add(plugins, plug)
  endfor

  if len(plugins) > 0
    echoerr "Loading plugins from" a:path "is deprecated. Please use janus#add_plugin."
  endif

  return plugins
endfunction

" Load plug groups
function! janus#load_plug()
  if !exists("g:loaded_plug")
    " Source plug
    exe 'source ' . g:janus_vim_path . '/core/plug/plug.vim'
  endif

  call janus#add_group("core", [
    \ ["before"],
    \ ["janus"],
    \ ])

  let plugins = []
  call extend(plugins, s:pending_plugins["core"])
  call extend(plugins, get(s:pending_plugins, "custom-before", []))
  call extend(plugins, s:get_legacy_custom_plugins(g:janus_custom_path . ".before"))
  call extend(plugins, s:pending_plugins["bundled"])
  call extend(plugins, s:get_legacy_custom_plugins(g:janus_custom_path))
  call extend(plugins, get(s:pending_plugins, "custom-after", []))

  call plug#begin(g:janus_vim_path . janus#separator() . "plugged")
  for plug in plugins
    if !has_key(plug, "disabled_reason")
      call call("plug#", plug["args"])
    endif
  endfor
  call plug#end()
endfunction

" Disable a plugin
"
" @param [String] The group the plugin belongs to, will be determined if
"                 no group were given. (Deprecated)
" @param [String] The plugin name
" @param [String] The reason why it is disabled
" @return [Bool]
function! janus#disable_plugin(...)
  if a:0 < 1 || a:0 > 3
    throw "The arguments to janus#disable_plugin() should be <name>, [reason]"
  elseif a:0 == 1
    let name = a:1
    let reason = -1
  elseif a:0 == 2
    let name = a:1
    let reason = a:2
  elseif a:0 == 3
    echoerr "The [group] argument to janus#disable_plugin is deprecated"
    let name = a:2
    let reason = a:3
  endif

  if !has_key(s:bundled_plugins, name)
    return 0
  endif
  let plug = s:bundled_plugins[name]

  " Check if we need to add it
  if has_key(plug, "disabled_reason")
    " Just update the reason if necessary.
    if reason != "No reason given." && plug["disabled_reason"] == -1
      let plug["disabled_reason"] = reason
    endif

    return 0
  endif

  let plug['disabled_reason'] = reason
endfunction

" Add custom plugin (to be loaded before bundled plugins)
"
" Same parameters as the Plug command.
function! janus#add_before_plugin(...)
  call s:add_pending_plugin("custom-before", "custom", a:000)
endfunction

" Add custom plugin
"
" Same parameters as the Plug command.
function! janus#add_plugin(...)
  call s:add_pending_plugin("custom-after", "custom", a:000)
endfunction

" Return the plugin path
"
" @param [String] The group the plugin belongs to, will be determined if
"                 no group were given. (Deprecated)
" @param [String] The plugin name
" @return [String] The plugin path relative to g:janus_vim_path
function! janus#plugin_path(...)
  if a:0 < 1 || a:0 > 2
    throw "The arguments to janus#plugin_path() should be [group], <name>"
  elseif a:0 == 1
    let name  = a:1
  else
    echoerr "The [group] argument to janus#plugin_path is deprecated"
    let name  = a:2
  endif

  return g:janus_vim_path . janus#separator() . "plugged" . janus#separator() . name
endfunction

" Is modules loaded?
"
" @param [String] The plugin name
" @return [Boolean]
function! janus#is_module_loaded(name)
  return len(janus#vim_files(janus#plugin_path(a:name))) > 0
endfunction

" Is plugin disabled?
"
" @param [String] The plugin name
function! janus#is_plugin_disabled(name)
  if !has_key(s:bundled_plugins, a:name)
    return 0
  endif
  let plug = s:bundled_plugins[a:name]

  return has_key(plug, "disabled_reason")
endfunction

" Is plugin enabled?
"
" @param [String] The plugin name
" @return [Boolean]
function! janus#is_plugin_enabled(name)
  return janus#is_module_loaded(a:name) && !janus#is_plugin_disabled(a:name)
endfunction

" Mapping function
"
" @param [String] The plugin name
" @param [String] The mapping command (map, vmap, nmap or imap)
" @param [String] The mapping keys
" @param [String]* The mapping action
function! janus#add_mapping(name, mapping_command, mapping_keys, ...)
  if len(a:000) < 1
    throw "The arguments to janus#add_mapping() should be <name> <mapping_command> <mapping_keys> <mapping_action> [mapping_action]*"
  endif

  if janus#is_plugin_enabled(a:name)
    let mapping_command = join(a:000)
  else
    if !janus#is_module_loaded(a:name)
      let reason = "Module is not loaded"
    elseif s:bundled_plugins[a:name]['disabled_reason'] == -1
      return 0
    else
      let reason = s:bundled_plugins[a:name]['disabled_reason']
    endif

    let mapping_command = "<ESC>:echo 'The plugin " . a:name . " is disabled for the following reason: " . reason . ".'<CR>"
  endif

  let mapping_list = [a:mapping_command, a:mapping_keys, mapping_command]
  exe join(mapping_list)
endfunction
