" lawrencium.vim - A Mercurial wrapper
" Maintainer:   Ludovic Chabant <http://ludovic.chabant.com>
" Version:      0.1

" Globals {{{

if !exists('g:lawrencium_debug')
    let g:lawrencium_debug = 0
endif

if (exists('g:loaded_lawrencium') || &cp) && !g:lawrencium_debug
    finish
endif

if (exists('g:loaded_lawrencium') && g:lawrencium_debug)
    echom "Reloaded Lawrencium."
endif
let g:loaded_lawrencium = 1

if !exists('g:lawrencium_hg_executable')
    let g:lawrencium_hg_executable = 'hg'
endif

if !exists('g:lawrencium_trace')
    let g:lawrencium_trace = 0
endif

if !exists('g:lawrencium_define_mappings')
    let g:lawrencium_define_mappings = 1
endif

" }}}

" Utility {{{

" Strips the ending slash in a path.
function! s:stripslash(path)
    return fnamemodify(a:path, ':s?[/\\]$??')
endfunction

" Normalizes the slashes in a path.
function! s:normalizepath(path)
    if exists('+shellslash') && &shellslash
        return substitute(a:path, '\\', '/', '')
    elseif has('win32')
        return substitute(a:path, '/', '\\', '')
    else
        return a:path
    endif
endfunction

" Like tempname() but with some control over the filename.
function! s:tempname(name, ...)
    let path = tempname()
    let result = fnamemodify(path, ':h') . '/' . a:name . fnamemodify(path, ':t')
    if a:0 > 0
        let result = result . a:1
    endif
    return result
endfunction

" Prints a message if debug tracing is enabled.
function! s:trace(message, ...)
   if g:lawrencium_trace || (a:0 && a:1)
       let message = "lawrencium: " . a:message
       echom message
   endif
endfunction

" Prints an error message with 'lawrencium error' prefixed to it.
function! s:error(message)
    echom "lawrencium error: " . a:message
endfunction

" Throw a Lawrencium exception message.
function! s:throw(message)
    let v:errmsg = "lawrencium: " . a:message
    throw v:errmsg
endfunction

" Finds the repository root given a path inside that repository.
" Throw an error if not repository is found.
function! s:find_repo_root(path)
    let path = s:stripslash(a:path)
    let previous_path = ""
    while path != previous_path
        if isdirectory(path . '/.hg/store')
            return simplify(fnamemodify(path, ':p'))
        endif
        let previous_path = path
        let path = fnamemodify(path, ':h')
    endwhile
    call s:throw("No Mercurial repository found above: " . a:path)
endfunction

" }}}

" Mercurial Repository {{{

" Let's define a Mercurial repo 'class' using prototype-based object-oriented
" programming.
"
" The prototype dictionary.
let s:HgRepo = {}

" Constructor
function! s:HgRepo.New(path) abort
    let newRepo = copy(self)
    let newRepo.root_dir = s:find_repo_root(a:path)
    call s:trace("Built new Mercurial repository object at : " . newRepo.root_dir)
    return newRepo
endfunction

" Gets a full path given a repo-relative path
function! s:HgRepo.GetFullPath(path) abort
    let root_dir = self.root_dir
    if a:path =~# '\v^[/\\]'
        let root_dir = s:stripslash(root_dir)
    endif
    return root_dir . a:path
endfunction

" Gets a list of files matching a root-relative pattern.
" If a flag is passed and is TRUE, a slash will be appended to all
" directories.
function! s:HgRepo.Glob(pattern, ...) abort
    let root_dir = self.root_dir
    if (a:pattern =~# '\v^[/\\]')
        let root_dir = s:stripslash(root_dir)
    endif
    let matches = split(glob(root_dir . a:pattern), '\n')
    if a:0 && a:1
        for idx in range(len(matches))
            if !filereadable(matches[idx])
                let matches[idx] = matches[idx] . '/'
            endif
        endfor
    endif
    let strip_len = len(root_dir)
    call map(matches, 'v:val[strip_len : -1]')
    return matches
endfunction

" Runs a Mercurial command in the repo
function! s:HgRepo.RunCommand(command, ...) abort
    " If there's only one argument, and it's a list, then use that as the
    " argument list.
    let arg_list = a:000
    if a:0 == 1 && type(a:1) == type([])
        let arg_list = a:1
    endif
    let hg_command = g:lawrencium_hg_executable . ' --repository ' . shellescape(s:stripslash(self.root_dir))
    let hg_command = hg_command . ' ' . a:command . ' ' . join(arg_list, ' ')
    call s:trace("Running Mercurial command: " . hg_command)
    return system(hg_command)
endfunction

" Repo cache map
let s:buffer_repos = {}

" Get a cached repo
function! s:hg_repo(...) abort
    " Use the given path, or the mercurial directory of the current buffer.
    if a:0 == 0
        if exists('b:mercurial_dir')
            let path = b:mercurial_dir
        else
            let path = s:find_repo_root(expand('%:p'))
        endif
    else
        let path = a:1
    endif
    " Find a cache repo instance, or make a new one.
    if has_key(s:buffer_repos, path)
        return get(s:buffer_repos, path)
    else
        let repo = s:HgRepo.New(path)
        let s:buffer_repos[path] = repo
        return repo
    endif
endfunction

" Sets up the current buffer with Lawrencium commands if it contains a file from a Mercurial repo.
" If the file is not in a Mercurial repo, just exit silently.
function! s:setup_buffer_commands() abort
    call s:trace("Scanning buffer '" . bufname('%') . "' for Lawrencium setup...")
    let do_setup = 1
    if exists('b:mercurial_dir')
        if b:mercurial_dir =~# '\v^\s*$'
            unlet b:mercurial_dir
        else
            let do_setup = 0
        endif
    endif
    try
        let repo = s:hg_repo()
    catch /^lawrencium\:/
        return
    endtry
    let b:mercurial_dir = repo.root_dir
    if exists('b:mercurial_dir') && do_setup
        call s:trace("Setting Mercurial commands for buffer '" . bufname('%'))
        call s:trace("  with repo : " . expand(b:mercurial_dir))
        silent doautocmd User Lawrencium
    endif
endfunction

augroup lawrencium_detect
    autocmd!
    autocmd BufNewFile,BufReadPost *     call s:setup_buffer_commands()
    autocmd VimEnter               *     if expand('<amatch>')==''|call s:setup_buffer_commands()|endif
augroup end

" }}}

" Buffer Commands Management {{{

" Store the commands for Lawrencium-enabled buffers so that we can add them in
" batch when we need to.
let s:main_commands = []

function! s:AddMainCommand(command) abort
    let s:main_commands += [a:command]
endfunction

function! s:DefineMainCommands()
    for command in s:main_commands
        execute 'command! -buffer ' . command
    endfor
endfunction

augroup lawrencium_main
    autocmd!
    autocmd User Lawrencium call s:DefineMainCommands()
augroup end

" }}}

" Commands Auto-Complete {{{

" Auto-complete function for commands that take repo-relative file paths.
function! s:ListRepoFiles(ArgLead, CmdLine, CursorPos) abort
    let matches = s:hg_repo().Glob(a:ArgLead . '*', 1)
    call map(matches, 's:normalizepath(v:val)')
    return matches
endfunction

" Auto-complete function for commands that take repo-relative directory paths.
function! s:ListRepoDirs(ArgLead, CmdLine, CursorPos) abort
    let matches = s:hg_repo().Glob(a:ArgLead . '*/')
    call map(matches, 's:normalizepath(v:val)')
    return matches
endfunction

" }}}

" Hg {{{

function! s:Hg(bang, ...) abort
    let repo = s:hg_repo()
    let output = call(repo.RunCommand, a:000, repo)
    if a:bang
        " Open the output of the command in a temp file.
        let temp_file = s:tempname('hg-output-', '.txt')
        execute 'pedit ' . temp_file
        wincmd p
        call append(0, split(output, '\n'))
    else
        " Just print out the output of the command.
        echo output
    endif
endfunction

" Include the generated HG usage file.
let s:usage_file = expand("<sfile>:h:h") . "/resources/hg_usage.vim"
if filereadable(s:usage_file)
    execute "source " . s:usage_file
else
    call s:error("Can't find the Mercurial usage file. Auto-completion will be disabled in Lawrencium.")
endif

function! s:CompleteHg(ArgLead, CmdLine, CursorPos)
    " Don't do anything if the usage file was not sourced.
    if !exists('g:lawrencium_hg_commands') || !exists('g:lawrencium_hg_options')
        return []
    endif

    " a:ArgLead seems to be the number 0 when completing a minus '-'.
    " Gotta find out why...
    let arglead = a:ArgLead
    if type(a:ArgLead) == type(0)
        let arglead = '-'
    endif

    " Try completing a global option, before any command name.
    if a:CmdLine =~# '\v^Hg(\s+\-[a-zA-Z0-9\-_]*)+$'
        return filter(copy(g:lawrencium_hg_options), "v:val[0:strlen(arglead)-1] ==# arglead")
    endif

    " Try completing a command (note that there could be global options before
    " the command name).
    if a:CmdLine =~# '\v^Hg\s+(\-[a-zA-Z0-9\-_]+\s+)*[a-zA-Z]+$'
        echom " - matched command"
        return filter(keys(g:lawrencium_hg_commands), "v:val[0:strlen(arglead)-1] ==# arglead")
    endif

    " Try completing a command's options.
    let cmd = matchstr(a:CmdLine, '\v(^Hg\s+(\-[a-zA-Z0-9\-_]+\s+)*)@<=[a-zA-Z]+')
    if strlen(cmd) > 0
        echom " - matched command option for " . cmd . " with : " . arglead
    endif
    if strlen(cmd) > 0 && arglead[0] ==# '-'
        if has_key(g:lawrencium_hg_commands, cmd)
            " Return both command options and global options together.
            let copts = filter(copy(g:lawrencium_hg_commands[cmd]), "v:val[0:strlen(arglead)-1] ==# arglead")
            let gopts = filter(copy(g:lawrencium_hg_options), "v:val[0:strlen(arglead)-1] ==# arglead")
            return copts + gopts
        endif
    endif

    " Just auto-complete with filenames unless it's an option.
    if arglead[0] ==# '-'
        return []
    else
        return s:ListRepoFiles(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction

call s:AddMainCommand("-bang -complete=customlist,s:CompleteHg -nargs=* Hg :call s:Hg(<bang>0, <f-args>)")

" }}}

" Hglog {{{
function! s:HgLog(...) abort
    let repo = s:hg_repo()
    let template = "'{rev}////{files}////{author}////{desc|strip}\n'"
    if a:0
        let log_text = repo.RunCommand('log', '--cwd', repo.root_dir, '--template', template, ' '.join(a:000))
    else
        let log_text = repo.RunCommand('log', '--template', template, expand('%'))
    endif

    let list = []
    for line in split(log_text, '\n')
        " Parse each log entry
        let ml = matchlist(line, '\v(.*)////(.*)////(.*)////(.*)')
        if len(ml) > 1
            let rev = ml[1]
            let files = split(ml[2], ' ')
            let author = ml[3]
            let desc = ml[4]
            for file in files
                " Format filename for quickfix list
                let filename = 'hg://'.s:stripslash(repo.root_dir).'//'.rev.'//'.file
                let text = author.' '.desc
                let entry = {'filename': filename, 'text': text}
                let list += [entry]
            endfor
        endif
    endfor
    " replace quickfix list with new entries
    call setqflist(list,'r')
endfunction

call s:AddMainCommand("-nargs=? -complete=customlist,s:ListRepoFiles Hglog :call s:HgLog(<f-args>)")

function! s:FileRead()
    let list = matchlist(expand('<amatch>'), '\vhg://(.*)//(.*)//(.*)')
    let repo = s:hg_repo(list[1])
    let rev  = list[2]
    let path = list[3]
    let ext = fnamemodify(path, ':e')

    " Read file into buffer
    exe '0r !hg --cwd '.repo.root_dir.' cat -r '.rev.' '.path

    " Set read-only and delete buffer when hidden
    set ro
    setlocal bufhidden=delete noswapfile nobackup
    exe 'filetype detect'

    " Setup mercurial commands
    let b:mercurial_dir = repo.root_dir
    call s:DefineMainCommands()
endfunction

augroup lawrencium_files
    au!
    " Should be au FileReadCmd?
    au BufReadCmd hg://**//[0-9]*//** exe s:FileRead()
augroup end

" }}}

" Hglogstat {{{
function! s:HgLogStat(...) abort
    " Get the repo
    " and the `hg log` output.
    let repo = s:hg_repo()
    if a:0
        if a:1 == '%'
            " Probably a better way to handle this
            let log_text = repo.RunCommand('log', '--stat', expand('%'))
        else
            let log_text = repo.RunCommand('log', '--stat', '--cwd', repo.root_dir, ' '.join(a:000))
        endif
    else
        let log_text = repo.RunCommand('log', '--stat')
    endif
    if log_text ==# '\v%^\s*%$'
        echo "No log."
    endif

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg status` output in there.
    let temp_file = s:tempname('hg-log-', '.txt')
    let log_lines = split(log_text, '\n')
    pclose
    execute 'vsplit ' . fnameescape(temp_file)

    setlocal previewwindow bufhidden=delete
    call append(0, log_lines)
    call cursor(1, 1)

    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it.
    let b:mercurial_dir = repo.root_dir
    setlocal buftype=nofile
    setlocal syntax=hglog

    " Make commands available.
    call s:DefineMainCommands()

    " Add some nice commands.
    command! -buffer          Hglogedit         :call s:HgLog_FileEdit()
    command! -buffer          Hglogdiff         :call s:HgLog_Diff()

    " Add some handy mappings.
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hglogedit<cr>
        nnoremap <buffer> <silent> <C-N> :call search('^changeset:', 'W')<cr>
        nnoremap <buffer> <silent> <C-P> :call search('^changeset:', 'Wb')<cr>
        nnoremap <buffer> <silent> <C-D> :Hglogdiff<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>
    endif
endfunction
call s:AddMainCommand("-nargs=? -complete=customlist,s:ListRepoFiles Hglogstat :call s:HgLogStat(<f-args>)")

function! s:HgLog_FileEdit() abort
    " Get changeset rev
    let rev = matchstr(getline(search('^changeset:', 'nb')), '\v(^changeset:\s+)@<=\d+')

    " Get the path of the file under the cursor, or files from changest we're in
    let line = getline('.')
    let path = matchstr(line, '\v(^\s)@<=[^|]*')

    if path == ''
        " Not on a path line, Edit all files in changeset
        " Get start/end offsets for curreng changeset
        let start = line('.')
        let end = search('^changeset:','nW') - 3
        if end < 1
            let end = line('$') - 3
        endif

        for line in range(start, end)
            " Try to match path
            let path = matchstr(getline(line), '\v(^\s)@<=[^|]*')
            if path != ''
                call s:HgEdit(0, path, rev)
            endif
        endfor
    else
        " Edit file on current line
        call s:HgEdit(0, path, rev)
    endif
endfunction

function! s:HgLog_Diff() abort
    let repo = s:hg_repo()

    " Get the path of the file the cursor is on.
    let line = getline('.')
    let path = matchstr(line, '\v(^\s)@<=[^|]*')

    " Get changeset rev
    let rev = matchstr(getline(search('^changeset:', 'nb')), '\v(^changeset:\s+)@<=\d+')

    call s:HgEdit(0, path, rev)
    call s:HgDiff_DiffThis()

    " Remember the repo it belongs to.
    let b:mercurial_dir = repo.root_dir
    " Make sure it's deleted when we move away from it.
    " setlocal bufhidden=delete
    " Make commands available.
    call s:DefineMainCommands()
    wincmd p
    execute 'diffthis'
endfunction

" }}}

" Hgstatus {{{

function! s:HgStatus() abort
    " Get the repo and the `hg status` output.
    let repo = s:hg_repo()
    let status_text = repo.RunCommand('status')
    if status_text ==# '\v%^\s*%$'
        echo "Nothing modified."
    endif

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg status` output in there.
    let temp_file = s:tempname('hg-status-', '.txt')
    let preview_height = &previewheight
    let status_lines = split(status_text, '\n')
    execute "setlocal previewheight=" . (len(status_lines) + 1)
    execute "pedit " . temp_file
    wincmd p
    call append(0, status_lines)
    call cursor(1, 1)
    " Make it a nice size.
    execute "setlocal previewheight=" . preview_height
    " Make sure it's deleted when we exit the window.
    setlocal bufhidden=delete

    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it.
    let b:mercurial_dir = repo.root_dir
    setlocal buftype=nofile
    setlocal syntax=hgstatus

    " Make commands available.
    call s:DefineMainCommands()

    " Add some nice commands.
    command! -buffer          Hgstatusedit      :call s:HgStatus_FileEdit()
    command! -buffer          Hgstatusdiff      :call s:HgStatus_Diff(0)
    command! -buffer          Hgstatusvdiff     :call s:HgStatus_Diff(1)
    command! -buffer          Hgstatusrefresh   :call s:HgStatus_Refresh()
    command! -buffer -range   Hgstatusaddremove :call s:HgStatus_AddRemove(<line1>, <line2>)
    command! -buffer -range=% -bang Hgstatuscommit  :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 0)
    command! -buffer -range=% -bang Hgstatusvcommit :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 1)

    " Add some handy mappings.
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hgstatusedit<cr>
        nnoremap <buffer> <silent> <C-N> :call search('^[MARC\!\?I ]\s.', 'We')<cr>
        nnoremap <buffer> <silent> <C-P> :call search('^[MARC\!\?I ]\s.', 'Wbe')<cr>
        nnoremap <buffer> <silent> <C-D> :Hgstatusdiff<cr>
        nnoremap <buffer> <silent> <C-V> :Hgstatusvdiff<cr>
        nnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        nnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
        nnoremap <buffer> <silent> <C-R> :Hgstatusrefresh<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>

        vnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        vnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
    endif

    " Make sure the file is deleted with the buffer.
    autocmd BufDelete <buffer> call s:HgStatus_CleanUp(expand('<afile>:p'))
endfunction

function! s:HgStatus_CleanUp(path) abort
    " If the `hg status` output has been saved to disk (e.g. because of a
    " refresh we did), let's delete it.
    if filewritable(a:path)
        call s:trace("Cleaning up status log: " . a:path)
        call delete(a:path)
    endif
endfunction

function! s:HgStatus_Refresh() abort
    " Get the repo and the `hg status` output.
    let repo = s:hg_repo()
    let status_text = repo.RunCommand('status')

    " Replace the contents of the current buffer with it, and refresh.
    echo "Writing to " . expand('%:p')
    let path = expand('%:p')
    let status_lines = split(status_text, '\n')
    call writefile(status_lines, path)
    edit
endfunction

function! s:HgStatus_FileEdit() abort
    " Get the path of the file the cursor is on.
    let filename = s:HgStatus_GetSelectedFile()

    " If the file is already open in a window, jump to that window.
    " Otherwise, jump to the previous window and open it there.
    for nr in range(1, winnr('$'))
        let br = winbufnr(nr)
        let bpath = fnamemodify(bufname(br), ':p')
        if bpath ==# filename
            execute nr . 'wincmd w'
            return
        endif
    endfor
    wincmd p
    execute 'edit ' . filename
endfunction

function! s:HgStatus_AddRemove(linestart, lineend) abort
    " Get the selected filenames.
    let filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['!', '?'])
    if len(filenames) == 0
        call s:error("No files to add or remove in selection or current line.")
    endif

    " Run `addremove` on those paths.
    let repo = s:hg_repo()
    call repo.RunCommand('addremove', filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_Commit(linestart, lineend, bang, vertical) abort
    " Get the selected filenames.
    let filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(filenames) == 0
        call s:error("No files to commit in selection or file.")
    endif

    " Run `Hgcommit` on those paths.
    call s:HgCommit(a:bang, a:vertical, filenames)
endfunction

function! s:HgStatus_Diff(vertical) abort
    " Open the file and run `Hgdiff` on it.
    call s:HgStatus_FileEdit()
    call s:HgDiff('%:p', a:vertical)
endfunction

function! s:HgStatus_GetSelectedFile() abort
    let filenames = s:HgStatus_GetSelectedFiles()
    return filenames[0]
endfunction

function! s:HgStatus_GetSelectedFiles(...) abort
    if a:0 >= 2
        let lines = getline(a:1, a:2)
    else
        let lines = []
        call add(lines, getline('.'))
    endif
    let filenames = []
    let repo = s:hg_repo()
    for line in lines
        if a:0 >= 3
            let status = s:HgStatus_GetFileStatus(line)
            if index(a:3, status) < 0
                continue
            endif
        endif
        " Yay, awesome, Vim's regex syntax is fucked up like shit, especially for
        " look-aheads and look-behinds. See for yourself:
        let filename = matchstr(line, '\v(^[MARC\!\?I ]\s)@<=.*')
        let filename = repo.GetFullPath(filename)
        call add(filenames, filename)
    endfor
    return filenames
endfunction

function! s:HgStatus_GetFileStatus(...) abort
    let line = a:0 ? a:1 : getline('.')
    return matchstr(line, '\v^[MARC\!\?I ]')
endfunction

call s:AddMainCommand("Hgstatus :call s:HgStatus()")

" }}}

" Hgcd, Hglcd {{{

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hgcd :cd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")
call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hglcd :lcd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")

" }}}

" Hgedit {{{

function! s:HgEdit(bang, filename, ...) abort
    let repo = s:hg_repo()

    if a:bang
        let cmd = 'edit! '
    else
        let cmd = 'edit '
    endif

    if a:0
        " Editing older revision of a file
        let rev = a:1

        " Create new file using same format as quickfix list, which will
        " trigger the file read
        let fn = 'hg://'.repo.root_dir.'//'.rev.'//'.a:filename
        exe cmd.fn
    else
        " Editing file in cwd
        let full_path = repo.GetFullPath(a:filename)
        execute cmd.full_path
    endif

    " Remember the repo it belongs to.
    let b:mercurial_dir = repo.root_dir
    " Make commands available.
    call s:DefineMainCommands()
endfunction
call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgedit :call s:HgEdit(<bang>0, <f-args>)")

" }}}

" Hgstatus {{{

function! s:HgStatus() abort
    " Get the repo and the `hg status` output.
    let repo = s:hg_repo()
    let status_text = repo.RunCommand('status')
    if status_text ==# '\v%^\s*%$'
        echo "Nothing modified."
    endif

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg status` output in there.
    let temp_file = s:tempname('hg-status-', '.txt')
    let preview_height = &previewheight
    let status_lines = split(status_text, '\n')
    execute "setlocal previewheight=" . (len(status_lines) + 1)
    execute "pedit " . temp_file
    wincmd p
    call append(0, status_lines)
    call cursor(1, 1)
    " Make it a nice size.
    execute "setlocal previewheight=" . preview_height
    " Make sure it's deleted when we exit the window.
    setlocal bufhidden=delete

    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it.
    let b:mercurial_dir = repo.root_dir
    setlocal buftype=nofile
    setlocal syntax=hgstatus

    " Make commands available.
    call s:DefineMainCommands()

    " Add some nice commands.
    command! -buffer          Hgstatusedit      :call s:HgStatus_FileEdit()
    command! -buffer          Hgstatusdiff      :call s:HgStatus_Diff(0)
    command! -buffer          Hgstatusvdiff     :call s:HgStatus_Diff(1)
    command! -buffer          Hgstatusrefresh   :call s:HgStatus_Refresh()
    command! -buffer -range   Hgstatusaddremove :call s:HgStatus_AddRemove(<line1>, <line2>)
    command! -buffer -range=% -bang Hgstatuscommit  :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 0)
    command! -buffer -range=% -bang Hgstatusvcommit :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 1)

    " Add some handy mappings.
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hgstatusedit<cr>
        nnoremap <buffer> <silent> <C-N> :call search('^[MARC\!\?I ]\s.', 'We')<cr>
        nnoremap <buffer> <silent> <C-P> :call search('^[MARC\!\?I ]\s.', 'Wbe')<cr>
        nnoremap <buffer> <silent> <C-D> :Hgstatusdiff<cr>
        nnoremap <buffer> <silent> <C-V> :Hgstatusvdiff<cr>
        nnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        nnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
        nnoremap <buffer> <silent> <C-R> :Hgstatusrefresh<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>

        vnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        vnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
    endif

    " Make sure the file is deleted with the buffer.
    autocmd BufDelete <buffer> call s:HgStatus_CleanUp(expand('<afile>:p'))
endfunction

function! s:HgStatus_CleanUp(path) abort
    " If the `hg status` output has been saved to disk (e.g. because of a
    " refresh we did), let's delete it.
    if filewritable(a:path)
        call s:trace("Cleaning up status log: " . a:path)
        call delete(a:path)
    endif
endfunction

function! s:HgStatus_Refresh() abort
    " Get the repo and the `hg status` output.
    let repo = s:hg_repo()
    let status_text = repo.RunCommand('status')

    " Replace the contents of the current buffer with it, and refresh.
    echo "Writing to " . expand('%:p')
    let path = expand('%:p')
    let status_lines = split(status_text, '\n')
    call writefile(status_lines, path)
    edit
endfunction

function! s:HgStatus_FileEdit() abort
    " Get the path of the file the cursor is on.
    let filename = s:HgStatus_GetSelectedFile()

    " If the file is already open in a window, jump to that window.
    " Otherwise, jump to the previous window and open it there.
    for nr in range(1, winnr('$'))
        let br = winbufnr(nr)
        let bpath = fnamemodify(bufname(br), ':p')
        if bpath ==# filename
            execute nr . 'wincmd w'
            return
        endif
    endfor
    wincmd p
    execute 'edit ' . filename
endfunction

function! s:HgStatus_AddRemove(linestart, lineend) abort
    " Get the selected filenames.
    let filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['!', '?'])
    if len(filenames) == 0
        call s:error("No files to add or remove in selection or current line.")
    endif

    " Run `addremove` on those paths.
    let repo = s:hg_repo()
    call repo.RunCommand('addremove', filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_Commit(linestart, lineend, bang, vertical) abort
    " Get the selected filenames.
    let filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(filenames) == 0
        call s:error("No files to commit in selection or file.")
    endif

    " Run `Hgcommit` on those paths.
    call s:HgCommit(a:bang, a:vertical, filenames)
endfunction

function! s:HgStatus_Diff(vertical) abort
    " Open the file and run `Hgdiff` on it.
    call s:HgStatus_FileEdit()
    call s:HgDiff('%:p', a:vertical)
endfunction

function! s:HgStatus_GetSelectedFile() abort
    let filenames = s:HgStatus_GetSelectedFiles()
    return filenames[0]
endfunction

function! s:HgStatus_GetSelectedFiles(...) abort
    if a:0 >= 2
        let lines = getline(a:1, a:2)
    else
        let lines = []
        call add(lines, getline('.'))
    endif
    let filenames = []
    let repo = s:hg_repo()
    for line in lines
        if a:0 >= 3
            let status = s:HgStatus_GetFileStatus(line)
            if index(a:3, status) < 0
                continue
            endif
        endif
        " Yay, awesome, Vim's regex syntax is fucked up like shit, especially for
        " look-aheads and look-behinds. See for yourself:
        let filename = matchstr(line, '\v(^[MARC\!\?I ]\s)@<=.*')
        let filename = repo.GetFullPath(filename)
        call add(filenames, filename)
    endfor
    return filenames
endfunction

function! s:HgStatus_GetFileStatus(...) abort
    let line = a:0 ? a:1 : getline('.')
    return matchstr(line, '\v^[MARC\!\?I ]')
endfunction

call s:AddMainCommand("Hgstatus :call s:HgStatus()")

" }}}

" Hgcd, Hglcd {{{

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hgcd :cd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")
call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hglcd :lcd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")

" }}}

" Hgdiff {{{

function! s:HgDiff(filename, vertical, ...) abort
    " Default revisions to diff: the working directory (special Lawrencium
    " hard-coded syntax) and the parent of the working directory (using
    " Mercurial's revsets syntax).
    let rev1 = 'lawrencium#_wdir_'
    let rev2 = ''
    if a:0 == 1
        let rev2 = a:1
    elseif a:0 == 2
        let rev1 = a:1
        let rev2 = a:2
    endif

    " Get the current repo, and expand the given filename in case it contains
    " fancy filename modifiers.
    let repo = s:hg_repo()
    let path = expand(a:filename)
    call s:trace("Diff'ing '".rev1."' and '".rev2."' on file: ".path)

    " We'll keep a list of buffers in this diff, so when one exits, the
    " others' 'diff' flag is turned off.
    let diff_buffers = []

    " Get the first file and open it.
    if rev1 == 'lawrencium#_wdir_'
        if bufexists(path)
            execute 'buffer ' . fnameescape(path)
        else
            execute 'edit ' . fnameescape(path)
        endif
        " Make it part of the diff group.
        call s:HgDiff_DiffThis()
    else
        " Nice filenames
        let fn = '--' . fnamemodify(path, ':t')
        let temp_file = fnamemodify(tempname(), ':p:h') . '/' . rev1 . fn

        " Use hg cat to create temporary copy of revision of file and edit
        call repo.RunCommand('cat', '-r', '"'.rev1.'"', path, '-o', temp_file)
        execute 'edit ' . fnameescape(temp_file)

        " Make it part of the diff group.
        call s:HgDiff_DiffThis()
        " Remember the repo it belongs to.
        let b:mercurial_dir = repo.root_dir
        " Make sure it's deleted when we move away from it.
        setlocal bufhidden=delete
        " Make commands available.
        call s:DefineMainCommands()
    endif

    " Get the second file and open it too.
    let diffsplit = 'diffsplit'
    if a:vertical
        let diffsplit = 'vertical diffsplit'
    endif
    if rev2 == 'lawrencium#_wdir_'
        execute diffsplit . ' ' . fnameescape(path)
    else
        " Nice filenames
        let fn = '--' . fnamemodify(path, ':t')

        " Get revision if we don't have it
        if rev2 == ''
            let fn = join(split(repo.RunCommand('id', '-r', '-1', '-n', '-b', '-t')), '-') . fn
        endif

        let temp_file = fnamemodify(tempname(), ':p:h') . '/' . rev2 . fn

        " Use hg cat to create temporary copy of revision of file and edit
        call repo.RunCommand('cat', '-r', '"'.rev2.'"', path, '-o', temp_file)
        execute diffsplit . ' ' . fnameescape(temp_file)

        " Remember the repo it belongs to.
        let b:mercurial_dir = repo.root_dir
        " Make sure it's deleted when we move away from it.
        setlocal bufhidden=delete
        " Make commands available.
        call s:DefineMainCommands()
    endif
endfunction

function! s:HgDiff_DiffThis() abort
    " Store some commands to run when we exit diff mode.
    " It's needed because `diffoff` reverts those settings to their default
    " values, instead of their previous ones.
    if !&diff
        call s:trace('Enabling diff mode on ' . bufname('%'))
        let w:lawrencium_diffoff = {}
        let w:lawrencium_diffoff['&diff'] = 0
        let w:lawrencium_diffoff['&wrap'] = &wrap
        let w:lawrencium_diffoff['&scrollopt'] = &scrollopt
        let w:lawrencium_diffoff['&scrollbind'] = &scrollbind
        let w:lawrencium_diffoff['&cursorbind'] = &cursorbind
        let w:lawrencium_diffoff['&foldmethod'] = &foldmethod
        let w:lawrencium_diffoff['&foldcolumn'] = &foldcolumn
        diffthis
    endif
endfunction

function! s:HgDiff_DiffOff(...) abort
    " Get the window name (given as a paramter, or current window).
    let nr = a:0 ? a:1 : winnr()

    " Run the commands we saved in `HgDiff_DiffThis`, or just run `diffoff`.
    let backup = getwinvar(nr, 'lawrencium_diffoff')
    if type(backup) == type({}) && len(backup) > 0
        call s:trace('Disabling diff mode on ' . nr)
        for key in keys(backup)
            call setwinvar(nr, key, backup[key])
        endfor
        call setwinvar(nr, 'lawrencium_diffoff', {})
    else
        call s:trace('Disabling diff mode on ' . nr . ' (but no true restore)')
        diffoff
    endif
endfunction

function! s:HgDiff_GetDiffWindows() abort
    let result = []
    for nr in range(1, winnr('$'))
        if getwinvar(nr, '&diff')
            call add(result, nr)
        endif
    endfor
    return result
endfunction

function! s:HgDiff_CleanUp() abort
    " If we're not leaving a diff window, do nothing.
    if !&diff
        return
    endif

    " If there will be only one diff window left (plus the one we're leaving),
    " turn off diff everywhere.
    let nrs = s:HgDiff_GetDiffWindows()
    if len(nrs) <= 2
        call s:trace('Disabling diff mode in ' . len(nrs) . ' windows.')
        for nr in nrs
            if getwinvar(nr, '&diff')
                call s:HgDiff_DiffOff(nr)
            endif
        endfor
    else
        call s:trace('Still ' . len(nrs) . ' diff windows open.')
    endif
endfunction

augroup lawrencium_diff
  autocmd!
  autocmd BufWinLeave * call s:HgDiff_CleanUp()
augroup end

call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgdiff :call s:HgDiff('%:p', 0, <f-args>)")
call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgvdiff :call s:HgDiff('%:p', 1, <f-args>)")

" }}}

" Hgcommit {{{

function! s:HgCommit(bang, vertical, ...) abort
    " Get the repo we'll be committing into.
    let repo = s:hg_repo()

    " Get the list of files to commit.
    " It can either be several files passed as extra parameters, or an
    " actual list passed as the first extra parameter.
    let filenames = []
    if a:0
        let filenames = a:000
        if a:0 == 1 && type(a:1) == type([])
            let filenames = a:1
        endif
    endif

    " Open a commit message file.
    let commit_path = s:tempname('hg-editor-', '.txt')
    let split = a:vertical ? 'vsplit' : 'split'
    execute split . ' ' . commit_path
    call append(0, ['', ''])
    call append(2, split(s:HgCommit_GenerateMessage(repo, filenames), '\n'))
    call cursor(1, 1)

    " Setup the auto-command that will actually commit on write/exit,
    " and make the buffer delete itself on exit.
    let b:mercurial_dir = repo.root_dir
    let b:lawrencium_commit_files = filenames
    setlocal bufhidden=delete
    setlocal syntax=hgcommit
    if a:bang
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 0)
    else
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 1)
    endif
    " Make commands available.
    call s:DefineMainCommands()
endfunction

let s:hg_status_messages = {
    \'M': 'modified',
    \'A': 'added',
    \'R': 'removed',
    \'C': 'clean',
    \'!': 'missing',
    \'?': 'not tracked',
    \'I': 'ignored',
    \' ': '',
    \}

function! s:HgCommit_GenerateMessage(repo, filenames) abort
    let msg  = "HG: Enter commit message. Lines beginning with 'HG:' are removed.\n"
    let msg .= "HG: Leave message empty to abort commit.\n"
    let msg .= "HG: Write and quit buffer to proceed.\n"
    let msg .= "HG: --\n"
    let msg .= "HG: user: " . split(a:repo.RunCommand('showconfig ui.username'), '\n')[0] . "\n"
    let msg .= "HG: branch '" . split(a:repo.RunCommand('branch'), '\n')[0] . "'\n"

    if len(a:filenames)
        let status_lines = split(a:repo.RunCommand('status', a:filenames), "\n")
    else
        let status_lines = split(a:repo.RunCommand('status'), "\n")
    endif
    for line in status_lines
        if line ==# ''
            continue
        endif
        let type = matchstr(line, '\v^[MARC\!\?I ]')
        let path = line[2:]
        let msg .= "HG: " . s:hg_status_messages[type] . ' ' . path . "\n"
    endfor

    return msg
endfunction

function! s:HgCommit_Execute(log_file, show_output) abort
    " Check if the user actually saved a commit message.
    if !filereadable(a:log_file)
        call s:error("abort: Commit message not saved")
        return
    endif

    call s:trace("Committing with log file: " . a:log_file)

    " Clean up all the 'HG:' lines from the commit message, and see if there's
    " any message left (Mercurial does this automatically, usually, but
    " apparently not when you feed it a log file...).
    let lines = readfile(a:log_file)
    call filter(lines, "v:val !~# '\\v^HG:'")
    if len(filter(copy(lines), "v:val !~# '\\v^\\s*$'")) == 0
        call s:error("abort: Empty commit message")
        return
    endif
    call writefile(lines, a:log_file)

    " Get the repo and commit with the given message.
    let repo = s:hg_repo()
    let hg_args = ['-l', a:log_file]
    call extend(hg_args, b:lawrencium_commit_files)
    let output = repo.RunCommand('commit', hg_args)
    if a:show_output && output !~# '\v%^\s*%$'
        call s:trace("Output from hg commit:", 1)
        for output_line in split(output, '\n')
            echom output_line
        endfor
    endif
endfunction

call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgcommit :call s:HgCommit(<bang>0, 0, <f-args>)")
call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgvcommit :call s:HgCommit(<bang>0, 1, <f-args>)")

" }}}

" Hginit {{{

function! s:HgInit() abort
    let hg_command = g:lawrencium_hg_executable . ' init'
    execute 'silent !' . hg_command | redraw!
    call s:setup_buffer_commands()
endfunction

command! Hginit :call s:HgInit()

" }}}

" Autoload Functions {{{

" Prints a summary of the current repo (if any) that's appropriate for
" displaying on the status line.
function! lawrencium#statusline(...)
    if !exists('b:mercurial_dir')
        return ''
    endif
    let prefix = (a:0 > 0 ? a:1 : '')
    let suffix = (a:0 > 1 ? a:2 : '')
    let branch = 'default'
    let branch_file = s:hg_repo().GetFullPath('.hg/branch')
    if filereadable(branch_file)
        let branch = readfile(branch_file)[0]
    endif
    return prefix . branch . suffix
endfunction

" Rescans the current buffer for setting up Mercurial commands.
" Passing '1' as the parameter enables debug traces temporarily.
function! lawrencium#rescan(...)
    if exists('b:mercurial_dir')
        unlet b:mercurial_dir
    endif
    if a:0 && a:1
        let trace_backup = g:lawrencium_trace
        let g:lawrencium_trace = 1
    endif
    call s:setup_buffer_commands()
    if a:0 && a:1
        let g:lawrencium_trace = trace_backup
    endif
endfunction

" Enables/disables the debug trace.
function! lawrencium#debugtrace(...)
    let g:lawrencium_trace = (a:0 == 0 || (a:0 && a:1))
    echom "Lawrencium debug trace is now " . (g:lawrencium_trace ? "enabled." : "disabled.")
endfunction

" }}}
