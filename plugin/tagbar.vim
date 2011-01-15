" ============================================================================
" File:        tagbar.vim
" Description: List the current file's tags in a sidebar, ordered by class etc
" Maintainer:  Jan Larres <jan@majutsushi.net>
" Licence:     Vim licence
" Website:     http://github.com/majutsushi/tagbar
" Note:        This plugin was heavily inspired by the 'Taglist' plugin by
"              Yegappan Lakshamanan and uses some small portions of code from
"              it.
" ============================================================================

if &cp || exists('g:loaded_tagbar')
    finish
endif

if !exists('*system')
    echomsg 'Tagbar: No system() function available, skipping plugin'
    finish
endif

if !exists('g:tagbar_ctags_exe')
    if executable('exuberant-ctags')
        let g:tagbar_ctags_exe = 'exuberant-ctags'
    elseif executable('exctags')
        let g:tagbar_ctags_exe = 'exctags'
    elseif executable('ctags')
        let g:tagbar_ctags_exe = 'ctags'
    elseif executable('ctags.exe')
        let g:tagbar_ctags_exe = 'ctags.exe'
    elseif executable('tags')
        let g:tagbar_ctags_exe = 'tags'
    else
        echomsg 'Tagbar: Exuberant ctags not found, skipping plugin'
        finish
    endif
endif

let g:loaded_tagbar = 1

if !exists('g:tagbar_left')
    let g:tagbar_left = 0
endif

if !exists('g:tagbar_width')
    let g:tagbar_width = 40
endif

if !exists('g:tagbar_types')
    let g:tagbar_types = {}
endif

if !exists('g:tagbar_autoclose')
    let g:tagbar_autoclose = 0
endif

function! s:InitTypes()
    let s:known_files = {}
    let s:known_types = {}

    let type_cpp = {}
    let type_cpp.ctagstype = 'c++'
    let type_cpp.scopes    = ['namespace', 'class', 'struct']
    let type_cpp.sro       = '::'
    let type_cpp.kinds     = [
        \ 'd:macros',
        \ 'n:namespaces',
        \ 'p:prototypes',
        \ 'v:variables',
        \ 't:typedefs',
        \ 'c:classes',
        \ 'm:members',
        \ 'g:enum',
        \ 's:structs',
        \ 'u:unions',
        \ 'f:functions'
    \ ]
    let type_cpp.scope2kind = {
        \ 'namespace' : 'n',
        \ 'class'     : 'c',
        \ 'struct'    : 's'
    \ }
    let s:known_types.cpp = type_cpp

    let type_python = {}
    let type_python.ctagstype = 'python'
    let type_python.scopes    = ['class', 'function']
    let type_python.sro       = '.'
    let type_python.kinds     = [
        \ 'i:imports',
        \ 'c:classes',
        \ 'f:functions',
        \ 'm:members',
        \ 'v:variables'
    \ ]
    let type_python.scope2kind = {
        \ 'class'    : 'c',
        \ 'function' : 'f'
    \ }
    let s:known_types.python = type_python

    call extend(s:known_types, g:tagbar_types)
endfunction

call s:InitTypes()

function! s:ToggleWindow()
    let tagbarwinnr = bufwinnr("__Tagbar__")
    if tagbarwinnr != -1
        call s:CloseWindow()
        return
    endif

    call s:OpenWindow()
endfunction

function! s:OpenWindow()
    " If the tagbar window is already open jump to it
    let tagbarwinnr = bufwinnr('__Tagbar__')
    if tagbarwinnr != -1 && winnr() != tagbarwinnr
"        execute tagbarwinnr . 'wincmd w'
        return
    endif

    let openpos = g:tagbar_left ? 'topleft vertical ' : 'botright vertical '
    execute 'silent! keepalt ' . openpos . g:tagbar_width . 'split ' . '__Tagbar__'

    setlocal noreadonly " in case the "view" mode is used
    setlocal buftype=nofile
    setlocal bufhidden=delete
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nomodifiable
    setlocal filetype=tagbar
    setlocal nolist
    setlocal nonumber
    setlocal norelativenumber
    setlocal nowrap
    setlocal winfixwidth

    setlocal foldenable
    setlocal foldminlines=0
    setlocal foldmethod=manual
    setlocal foldlevel=9999
    setlocal foldcolumn=1
    setlocal foldtext=v:folddashes.getline(v:foldstart)

    let cpoptions_save = &cpoptions
    set cpoptions&vim

"    nnoremap <script> <silent> <buffer> k :call <sid>GundoMove(-1)<CR>

    augroup TagbarAutoCmds
        autocmd!
        autocmd BufEnter  __Tagbar__ nested call s:QuitIfOnlyWindow()
        autocmd BufUnload __Tagbar__ call s:CleanUp()
"        autocmd CursorHold __Tag_List__ call s:Tlist_Window_Show_Info()

        autocmd BufEnter * call s:RefreshContent()
"        autocmd TabEnter * silent call s:Tlist_Refresh_Folds()
"        autocmd CursorHold * silent call s:Tlist_Window_Highlight_Tag(
"                            \ fnamemodify(bufname('%'), ':p'), line('.'), 1, 0)
    augroup END

    let &cpoptions = cpoptions_save

    execute 'wincmd p'
endfunction

function! s:CloseWindow()
    let tagbarwinnr = bufwinnr('__Tagbar__')
    if tagbarwinnr == -1
        return
    endif

    if winnr() == tagbarwinnr
        if winbufnr(2) != -1
            " Other windows are open, only close the tagbar one
            close
        endif
    else
        " Go to the tagbar window, close it and then come back to the
        " original window
        let curbufnr = bufnr('%')
        exe tagbarwinnr . 'wincmd w'
        close
        " Need to jump back to the original window only if we are not
        " already in that window
        let winnum = bufwinnr(curbufnr)
        if winnr() != winnum
            exe winnum . 'wincmd w'
        endif
    endif
endfunction

function! s:CleanUp()
    silent! autocmd! TagbarAutoCmds
endfunction

function! s:QuitIfOnlyWindow()
    " Before quitting Vim, delete the tagbar buffer so that
    " the '0 mark is correctly set to the previous buffer.
    if winbufnr(2) == -1
        " Check if there is more than one tab page
        if tabpagenr('$') == 1
            bdelete
            quit
        else
            close
        endif
    endif
endfunction

function! s:RefreshContent()
    let fname = fnamemodify(bufname('%'), ':p')

    if !s:IsValidFile(fname, &filetype)
        return
    endif

    if has_key(s:known_files, fname)
        if s:known_files[fname].mtime != getftime(fname)
            call s:ProcessFile(fname, &filetype)
        endif
    else
        call s:ProcessFile(fname, &filetype)
    endif

    let tagbarwinnr = bufwinnr('__Tagbar__')

    if tagbarwinnr != -1
        call s:RenderContent(fname, &filetype)
    endif
endfunction

function! s:IsValidFile(fname, ftype)
    if a:fname == '' || a:ftype == ''
        return 0
    endif

    if !filereadable(a:fname)
        return 0
    endif

    if !has_key(s:known_types, a:ftype)
        return 0
    endif

    return 1
endfunction

function! s:ProcessFile(fname, ftype)
    let ctags_args = ' -f - --format=2 --excmd=pattern --fields=nksaz --extra= '

    let ctags_args .= ' --sort=yes '

    let ctags_type = s:known_types[a:ftype].ctagstype
    let ctags_kinds = ""
    for kind in s:known_types[a:ftype].kinds
        let [short, full] = split(kind, ':')
        let ctags_kinds .= short
    endfor

    let ctags_args .= ' --language-force=' . ctags_type .
                    \ ' --' . ctags_type . '-kinds=' . ctags_kinds . ' '

    let ctags_cmd = g:tagbar_ctags_exe . ctags_args . shellescape(a:fname)
    let ctags_output = system(ctags_cmd)

    if v:shell_error
        let msg = 'Tagbar: Could not generate tags for ' . a:fname
        call s:PrintWarningMsg(msg)
        if !empty(ctags_output)
            call s:PrintWarningMsg(ctags_output)
        endif
        return
    endif

    let fileinfo = {}
    let fileinfo.mtime = getftime(a:fname)

    let taglist = split(ctags_output, '\n\+')

    let fileinfo.tags = []

    for line in taglist
        let taginfo = s:ParseTagline(line)
        call add(fileinfo.tags, taginfo)
    endfor

    let s:known_files[a:fname] = fileinfo
endfunction

" name<TAB>file<TAB>expattern;"fields
" fields: <TAB>name:value
" fields that are always present: kind, line
function! s:ParseTagline(line)
    let parts = split(a:line, ';"')

    let taginfo = {}

    let basic_info      = split(parts[0], '\t')
    let taginfo.name    = basic_info[0]
    let taginfo.file    = basic_info[1]
    let taginfo.pattern = basic_info[2]

    let taginfo.fields = {}
    let fields = split(parts[1], '\t')
    for field in fields
        " can't use split() since the value can contain ':'
        let delimit             = stridx(field, ':')
        let key                 = strpart(field, 0, delimit)
        let val                 = strpart(field, delimit + 1)
        let taginfo.fields[key] = val
    endfor

    return taginfo
endfunction

function! s:RenderContent(fname, ftype)
    let tagbarwinnr = bufwinnr('__Tagbar__')

    execute tagbarwinnr . 'wincmd w'

    let lazyredraw_save = &lazyredraw
    set lazyredraw

    setlocal modifiable

    silent! %delete _

    let typeinfo = s:known_types[a:ftype]
    let tags     = copy(s:known_files[a:fname].tags)

    if has_key(typeinfo, 'scopes') && !empty(typeinfo.scopes)
        for scope in typeinfo.scopes
            let members = filter(copy(tags), 'has_key(v:val.fields, scope)')

            " remove tags in this scope from the tag list so they
            " don't get displayed twice
            call filter(tags, '!has_key(v:val.fields, scope)')

            if empty(members)
                continue
            endif

            let entries = {}

            " sort tags under their scope structure name
            " TODO: preserve order of scopes
            for member in members
                let scopevalue = member.fields[scope]
                if has_key(entries, scopevalue)
                    let entries[scopevalue] += [member]
                else
                    let entries[scopevalue]  = [member]
                endif
            endfor

            " print scope content
            for key in sort(keys(entries))
                silent! put =key . ' : ' . scope

                for entry in entries[key]
                    if has_key(entry.fields, 'signature')
                        let sig = ' ' . entry.fields.signature
                    else
                        let sig = ''
                    endif
                    silent! put =' ' . entry.name . sig
                endfor

                silent! put _
            endfor

            " remove the scoping structure from the tag list since we
            " don't need to display it separately again
            let scopekind = typeinfo.scope2kind[scope]
            call filter(tags, 'v:val.fields.kind != scopekind')
        endfor
    endif

    for kind in typeinfo.kinds
        let curtags = filter(copy(tags), 'v:val.fields.kind == kind[0]')

        if empty(curtags)
            continue
        endif

        silent! put =strpart(kind, 2)

        for tag in curtags
            silent! put =' ' . tag.name
        endfor

        silent! put _
    endfor

    setlocal nomodifiable

    let &lazyredraw = lazyredraw_save

    execute 'wincmd p'
endfunction

function! s:PrintWarningMsg(msg)
    echohl WarningMsg
    echomsg a:msg
    echohl None
endfunction

command! -nargs=0 TagbarToggle call s:ToggleWindow()
command! -nargs=0 TagbarOpen   call s:OpenWindow()
command! -nargs=0 TagbarClose  call s:CloseWindow()

" vim: ts=8 sw=4 sts=4 et foldenable foldmethod=syntax foldcolumn=1
