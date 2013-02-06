" Check python support
if !has('python')
    echo "Error: PyLint required vim compiled with +python."
    finish
endif

if !exists('g:PyLintOnWrite')
    let g:PyLintOnWrite = 1
endif

" Call PyLint only on write
if g:PyLintOnWrite
    augroup PyLintPlugin
        au BufWritePost <buffer> call s:PyLintOnWrite()
        au CursorHold <buffer> call s:GetPyLintMessage()
        au CursorMoved <buffer> call s:GetPyLintMessage()
    augroup end
endif

let b:showing_message = 0
"
" Check for pylint plugin is loaded
if exists("g:PyLintDirectory")
    finish
endif
" Init variables
let g:PyLintDirectory = expand('<sfile>:p:h')
if !exists('g:PyLintDissabledMessages')
    let g:PyLintDissabledMessages = 'C0103,C0111,C0301,W0141,W0142,W0212,W0221,W0223,W0232,W0401,W0613,W0631,E1101,E1120,R0903,R0904,R0913'
endif
if !exists('g:PyLintGeneratedMembers')
    let g:PyLintGeneratedMembers = 'REQUEST,acl_users,aq_parent,objects,DoesNotExist,_meta,status_code,content,context'
endif
if !exists('g:PyLintCWindow')
    let g:PyLintCWindow = 8
endif
if !exists('g:PyLintSigns')
    let g:PyLintSigns = 1
endif


" Commands
command! PyLintToggle :let b:pylint_disabled = exists('b:pylint_disabled') ? b:pylint_disabled ? 0 : 1 : 1
command! PyLint :call s:PyLint()
command! PyLintAuto :call s:PyLintAuto()

" Signs definition
sign define W text=WW texthl=Todo
sign define C text=CC texthl=Comment
sign define R text=RR texthl=Visual
sign define E text=EE texthl=Error

python << EOF

import sys, vim, cStringIO

sys.path.insert(0, vim.eval("g:PyLintDirectory"))
from logilab.astng.builder import MANAGER
from pylint import lint, checkers
from pep8.autopep8 import fix_file
import re

class Options():
    verbose = 0
    diff = False
    in_place = True
    recursive = False
    pep8_passes = 100
    max_line_length = 79
    ignore = ''
    select = ''
    aggressive = False

linter = lint.PyLinter()
checkers.initialize(linter)
linter.set_option('output-format', 'parseable')
linter.set_option('disable', vim.eval("g:PyLintDissabledMessages"))
linter.set_option('reports', 0)

def check():
    target = vim.eval("expand('%:p')")
    MANAGER.astng_cache.clear()
    linter.reporter.out = cStringIO.StringIO()
    linter.check(target)
    output = unicode(linter.reporter.out.getvalue(), 'utf-8')
    out = re.escape(output if output else "")
    vim.command('let b:pylint_output = "%s"' % out)


def fix_current_file():
    fix_file(vim.current.buffer.name, Options)

EOF

function! s:PyLintOnWrite()
    if !g:PyLintOnWrite or b:pylint_disabled
        return
    endif
    call s:PyLint()
endfunction

function! s:PyLint()
    if &modifiable && &modified
        write
    endif	

    py check()

    let b:qf_list = []
    let s:matchDict = {}
    let b:matchedlines = {}
    for error in split(b:pylint_output, "\n")
        let b:parts = matchlist(error, '\v([A-Za-z\.]+):(\d+): \[([EWRCI])[^\]]*\] (.*)')

        if len(b:parts) > 3

            " Store the error for the quickfix window
            let l:qf_item = {}
            let l:qf_item.filename = expand('%')
            let l:qf_item.bufnr = bufnr(b:parts[1])
            let l:qf_item.lnum = b:parts[2]
            let s:matchDict[b:parts[2]] = b:parts[4]
            let l:qf_item.type = b:parts[3]
            let l:qf_item.text = b:parts[4]
            call add(b:qf_list, l:qf_item)

        endif

    endfor
    "

    call setqflist(b:qf_list, 'r')
    " Place signs
    if g:PyLintSigns
        call s:PlacePyLintSigns()
    endif

    " Open cwindow
    if g:PyLintCWindow
        cclose
        if len(b:qf_list)
            let l:winsize = len(b:qf_list) > g:PyLintCWindow ? g:PyLintCWindow : len(b:qf_list)
            exec l:winsize . 'cwindow'
        endif
    endif
endfunction


fun! s:PyLintAuto() "{{{
    if &modifiable && &modified
        try
            write
        catch /E212/
            echohl Error | echo "File modified and I can't save it. Cancel operation." | echohl None
            return 0
        endtry
    endif
    py fix_file(vim.current.buffer.name, Options)
    cclose
    edit
endfunction "}}}

function! s:PlacePyLintSigns()
    "first remove all sings
    sign unplace *

    "now we place one sign for every quickfix line
    let l:id = 1
    for item in getqflist()
        execute(':sign place '.l:id.' name='.l:item.type.' line='.l:item.lnum.' buffer='.l:item.bufnr)
        let l:id = l:id + 1
    endfor
endfunction

" keep track of whether or not we are showing a message
" WideMsg() prints [long] message up to (&columns-1) length
" guaranteed without "Press Enter" prompt.
if !exists("*s:WideMsg")
    function s:WideMsg(msg)
        let x=&ruler | let y=&showcmd
        set noruler noshowcmd
        redraw
        echo strpart(a:msg, 0, &columns-1)
        let &ruler=x | let &showcmd=y
    endfun
endif


if !exists("*s:GetPyLintMessage")
    function s:GetPyLintMessage()
        let s:cursorPos = getpos(".")

        " Bail if RunPyflakes hasn't been called yet.
        if !exists('s:matchDict')
            return
        endif

        " if there's a message for the line the cursor is currently on, echo
        " it to the console
        if has_key(s:matchDict, s:cursorPos[1])
            let s:pyflakesMatch = get(s:matchDict, s:cursorPos[1])
            call s:WideMsg(s:pyflakesMatch)
            let b:showing_message = 1
            return
        endif

        " otherwise, if we're showing a message, clear it
        if b:showing_message == 1
            echo
            let b:showing_message = 0
        endif
    endfunction
endif
