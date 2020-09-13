func! neuron#add_virtual_titles()
	if !exists("w:cache_zettels")
		return
	end
	if !exists('*nvim_buf_set_virtual_text')
		return
	endif
	let l:ns = nvim_create_namespace('neuron')
	call nvim_buf_clear_namespace(0, l:ns, 0, -1)
	let l:re_neuron_link = '\[\[\[\?\([0-9a-zA-Z_-]\+\)\(?cf\)\?\]\]\]\?'
	let l:lnum = -1
	for line in getline(1, "$")
		let l:lnum += 1
		let l:zettel_id = util#get_zettel_in_line(line)
		if empty(l:zettel_id)
			continue
		endif
		let l:title = w:cache_titles[l:zettel_id]
		" TODO: Use
		" nvim_buf_set_extmark({buffer}, {ns_id}, {id}, {line}, {col}, {opts})
		" function instead of nvim_buf_set_virtual_text. Check this link for
		" help https://github.com/neovim/neovim/blob/e628a05b51d4620e91662f857d29f1ac8fc67862/runtime/doc/api.txt#L1935-L1955
		call nvim_buf_set_virtual_text(0, l:ns, l:lnum, [[l:title, g:style_virtual_title]], {})
	endfor
endf

func! neuron#insert_zettel_select(as_folgezettel)
	if a:as_folgezettel
		let l:sink_to_use = 'util#insert_shrink_fzf_folgezettel'
	else
		let l:sink_to_use = 'util#insert_shrink_fzf'
	endif

	call fzf#run(fzf#wrap({
		\ 'options': util#get_fzf_options(),
		\ 'source': w:list_pair_zettelid_zetteltitle,
		\ 'sink': function(l:sink_to_use),
	\ }, g:neuron_fullscreen_search))
endf

func! neuron#search_content(use_cursor)
	let w:last = expand('%s')
	let l:query = ""
	if a:use_cursor
		let l:query = expand("<cword>")
	endif
	call fzf#vim#ag(l:query, g:neuron_fullscreen_search)
endf

func! neuron#edit_zettel_select()
	call fzf#run(fzf#wrap({
		\ 'options': util#get_fzf_options(),
		\ 'source': w:list_pair_zettelid_zetteltitle,
		\ 'sink': function('util#edit_shrink_fzf'),
	\ }, g:neuron_fullscreen_search))
endf

func! neuron#edit_zettel_last()
	if !exists("w:last")
		call util#handlerr('E6')
		return
	end

	let l:file = w:last
	let w:last = expand('%s')
	exec 'edit '.l:file
endf

func! neuron#insert_zettel_last(as_folgezettel)
	if !exists("w:last")
		call util#handlerr('E6')
		return
	end

	let l:zettelid = fnamemodify(w:last, ':t:r')
	call util#insert(l:zettelid, a:as_folgezettel)
endf

func! neuron#edit_zettel_new()
	let w:last = expand('%s')
	exec 'edit '.system('neuron -d '.shellescape(g:zkdir).' new')
endf

func! neuron#edit_zettel_new_from_cword()
	let w:last = expand('%s')
	let l:title = expand("<cword>")
	exec 'edit '.system('neuron -d '.shellescape(g:zkdir).' new "'.l:title.'"')
endf

func! neuron#edit_zettel_new_from_visual()
	let w:last = expand('%s')
	" title from visual selection
	let l:vs = split(util#get_visual_selection(), "\n")
	let l:title = l:vs[0]

	" let l:content = l:vs[1:]
	exec 'edit '.system('neuron -d '.shellescape(g:zkdir).' new "'.l:title.'"')
endf


func! neuron#edit_zettel_under_cursor()
	let l:zettel_id = trim(expand('<cword>'), "<>[]")
	if util#is_zettelid_valid(l:zettel_id)
		call neuron#edit_zettel(l:zettel_id)
	else
		let l:zettel_id = trim(expand('<cWORD>'), "<>[]")
		if util#is_zettelid_valid(l:zettel_id)
			call neuron#edit_zettel(l:zettel_id)
		else
			call util#handlerr('E3')
		endif
	endif
endf

func! neuron#edit_zettel(zettel_id)
	let w:last = expand('%s')
	let l:file = g:zkdir.a:zettel_id.g:zextension
	exec 'edit '.l:file
endf

func! neuron#refresh_cache()
	try
		if !executable(g:path_neuron)
			call util#handlerr('E1')
		endif
	endtry

	let l:cmd = [g:path_neuron, "-d", g:zkdir, "query", "--uri", "z:zettels"]
	if has('nvim')
		call jobstart(l:cmd, {
			\ 'on_stdout': function('s:refresh_cache_callback_nvim'),
			\ 'stdout_buffered': 1
		\ })
	elseif has('job')
		let l:jobopt = {
			\ 'exit_cb': function('s:refresh_cache_callback_vim'),
			\ 'out_io': 'file',
			\ 'out_name': '/tmp/neuronzettelsbuffer',
			\ 'err_io': 'out'
		\ }
		if has('patch-8.1.350')
			let l:jobopt['noblock'] = 1
		endif
		call job_start(l:cmd, l:jobopt)
	else
		let l:cmd[2] = shellescape(g:zkdir)
		let l:data = system(join(cmd))
		call s:refresh_cache_callback(l:data)
	endif
endf

" vim 8
func! s:refresh_cache_callback_vim(channel, x)
	let l:data = readfile("/tmp/neuronzettelsbuffer")
	call job_start("rm /tmp/neuronzettelsbuffer")
	call s:refresh_cache_callback(join(l:data))
endf

" neovim
func s:refresh_cache_callback_nvim(id, data, event)
	call s:refresh_cache_callback(join(a:data))
endf

func! s:refresh_cache_callback(data)
	let l:zettels = json_decode(a:data)["result"]

	call sort(l:zettels, function('util#zettel_date_sorter'))

	let w:cache_titles = {}
	let w:cache_zettels = []
	let w:list_pair_zettelid_zetteltitle = []

	for z in l:zettels
		let w:cache_titles[z['zettelID']] = z['zettelTitle']
		let w:cache_zettels = add(w:cache_zettels, { 'id': z['zettelID'], 'title': z['zettelTitle'], 'path': z['zettelPath'] })
		let w:list_pair_zettelid_zetteltitle = add(w:list_pair_zettelid_zetteltitle, z['zettelID'].":".substitute(z['zettelTitle'], ':', '-', ''))
	endfor

 	call neuron#add_virtual_titles()
endf

let w:must_refresh_on_write = 0
func! neuron#on_write()
	if w:must_refresh_on_write
		call neuron#refresh_cache()
	else
		call neuron#add_virtual_titles()
	end
endf
