" vim-llm-teacher.vim
" A vim plugin to teach vim usage using an LLM

" Configuration variables
if !exists('g:vim_llm_model')
    let g:vim_llm_model = 'gemini/gemini-2.5-flash-preview-05-20'
endif

if !exists('g:vim_llm_context_lines')
    let g:vim_llm_context_lines = 10
endif

" Function to get current buffer context
function! GetBufferContext()
    let l:context = ""
    
    " Get current position
    let l:cur_line = line('.')
    let l:cur_col = col('.')
    let l:total_lines = line('$')
    
    " Determine context range
    let l:start_line = max([1, l:cur_line - g:vim_llm_context_lines])
    let l:end_line = min([l:total_lines, l:cur_line + g:vim_llm_context_lines])
    
    " Build context with line numbers
    let l:context .= "Current buffer context:\n"
    let l:context .= "```\n"
    
    for l:line_num in range(l:start_line, l:end_line)
        let l:line_content = getline(l:line_num)
        if l:line_num == l:cur_line
            " Mark current line and cursor position
            let l:prefix = printf("%4d > ", l:line_num)
            let l:context .= l:prefix . l:line_content . "\n"
            " Add cursor position indicator
            let l:cursor_indicator = repeat(' ', len(l:prefix) + l:cur_col - 1) . '^'
            let l:context .= l:cursor_indicator . " (cursor here)\n"
        else
            let l:context .= printf("%4d   ", l:line_num) . l:line_content . "\n"
        endif
    endfor
    
    let l:context .= "```\n"
    
    " Add file type info
    let l:context .= "File type: " . &filetype . "\n"
    
    return l:context
endfunction

" Main function to query LLM for vim commands
function! VimLLMTeacher(query, include_context)
    " Store the query for potential explanation
    let s:last_query = a:query
    
    " Build the prompt
    let l:prompt = "You are a vim expert. "
    
    " Add buffer context if requested
    if a:include_context
        let l:prompt .= GetBufferContext() . "\n"
    endif
    
    let l:prompt .= "The user wants to know how to: " . a:query . "\n\n"
    let l:prompt .= "Provide the vim command followed by a brief explanation. Format: 'command | explanation'. "
    let l:prompt .= "Concatenate commands directly (e.g. 'ggVG' not 'gg then VG'). "
    let l:prompt .= "Examples: 'dw | d: delete operator; w: word motion' or 'ggVG | gg: go to start; V: visual line mode; G: go to end' or 'ci\" | c: change operator; i\": inside quotes text object'\n"
    let l:prompt .= "For Ex commands, use just ':reg' not ':reg<CR>'. "
    let l:prompt .= "For search commands that need Enter, use just '/pattern' not '/pattern<CR>'."
    
    if a:include_context
        let l:prompt .= "\nConsider the cursor position when suggesting commands."
    endif
    
    " Escape the prompt for shell
    let l:escaped_prompt = shellescape(l:prompt)
    
    " Call llm binary
    let l:cmd = 'llm -m ' . g:vim_llm_model . ' ' . l:escaped_prompt
    let l:result = system(l:cmd)
    
    " Check for errors
    if v:shell_error != 0
        echohl ErrorMsg
        echo "Error calling LLM: " . l:result
        echohl None
        return
    endif
    
    " Clean up the result
    let l:result = substitute(l:result, '\n\+$', '', '')
    
    " Parse command and explanation if present
    if match(l:result, ' | ') != -1
        let l:parts = split(l:result, ' | ', 1)
        let l:command = l:parts[0]
        let l:explanation = len(l:parts) > 1 ? l:parts[1] : ''
    else
        let l:command = l:result
        let l:explanation = ''
    endif
    
    " Store for later use
    let s:last_command = l:command
    let s:last_explanation = l:explanation
    
    " Display the result
    echo ""
    echohl Question
    echo "Query: " . a:query
    echohl None
    echo "Command: " . l:command
    if l:explanation != ''
        echohl Comment
        echo "Concept: " . l:explanation
        echohl None
    endif
    echo ""
    
    " Ask for confirmation
    let l:choice = confirm("Execute this command?", "&Yes\n&No\n&Register (copy)\n&? (explain)", 1)
    
    if l:choice == 1
        " Execute the command
        call VimLLMExecute(l:command)
    elseif l:choice == 3
        " Copy to register
        let @" = l:command
        echo "Command copied to unnamed register"
    elseif l:choice == 4
        " Explain the command
        call VimLLMExplain()
    endif
endfunction

" Function to explain the last command
function! VimLLMExplain()
    if !exists('s:last_command') || !exists('s:last_query')
        echo "No command to explain"
        return
    endif
    
    let l:prompt = "You are a vim expert. The user asked how to: " . s:last_query . "\n"
    let l:prompt .= "The suggested command was: " . s:last_command . "\n\n"
    let l:prompt .= "Provide a detailed explanation breaking down each part of the command. "
    let l:prompt .= "Format: 'command | detailed explanation'. "
    let l:prompt .= "Examples: 'dw | d: delete operator; w: word motion' or 'ggVG | gg: go to start; V: visual line mode; G: go to end' or 'ci\" | c: change operator; i\": inside quotes text object'"
    
    let l:escaped_prompt = shellescape(l:prompt)
    let l:cmd = 'llm -m ' . g:vim_llm_model . ' ' . l:escaped_prompt
    let l:explanation = system(l:cmd)
    
    if v:shell_error != 0
        echohl ErrorMsg
        echo "Error getting explanation"
        echohl None
        return
    endif
    
    " Clean up and parse explanation
    let l:explanation = substitute(l:explanation, '\n\+$', '', '')
    
    " Parse command and explanation if present
    if match(l:explanation, ' | ') != -1
        let l:parts = split(l:explanation, ' | ', 1)
        let l:detailed_explanation = len(l:parts) > 1 ? l:parts[1] : l:explanation
    else
        let l:detailed_explanation = l:explanation
    endif
    
    echo ""
    echohl Title
    echo "Explanation: "
    echohl None
    echo l:detailed_explanation
    echo ""
    
    " Ask again what to do
    let l:choice = confirm("Now what?", "&Yes (execute)\n&No (cancel)\n&Register (copy)", 2)
    
    if l:choice == 1
        call VimLLMExecute(s:last_command)
    elseif l:choice == 3
        let @" = s:last_command
        echo "Command copied to unnamed register"
    endif
endfunction

" Function to execute vim commands safely
function! VimLLMExecute(commands)
    let l:command = trim(a:commands)
    
    " Remove common suffixes that LLMs might add
    let l:command = substitute(l:command, '<CR>$', '', '')
    let l:command = substitute(l:command, '<Enter>$', '', '')
    
    " Try to execute
    try
        if l:command =~ '^:'
            " Ex command - remove the colon and execute directly
            execute l:command[1:]
        elseif l:command =~ '^/'
            " Search command - add CR for execution
            execute 'normal! ' . l:command . "\<CR>"
        else
            " Normal mode command
            execute 'normal! ' . l:command
        endif
    catch
        echohl ErrorMsg
        echo "Error executing: " . l:command . " - " . v:exception
        echohl None
        return
    endtry
    
    echo "Command executed successfully!"
endfunction

" Interactive input functions
function! VimLLMInteractive()
    let l:query = input('Vim action: ')
    if l:query != ''
        call VimLLMTeacher(l:query, 0)
    endif
endfunction

function! VimLLMInteractiveContext()
    let l:query = input('Vim action (with context): ')
    if l:query != ''
        call VimLLMTeacher(l:query, 1)
    endif
endfunction

" Command definitions
command! -nargs=? VT if <q-args> != '' | call VimLLMTeacher(<q-args>, 0) | else | call VimLLMInteractive() | endif
command! -nargs=? VTC if <q-args> != '' | call VimLLMTeacher(<q-args>, 1) | else | call VimLLMInteractiveContext() | endif
command! -nargs=1 VimTeachModel let g:vim_llm_model = <q-args>

" Key mappings - simple and clean
nnoremap <leader>vt :VT<CR>
vnoremap <leader>vt :VT<CR>
nnoremap <leader>vtc :VTC<CR>
vnoremap <leader>vtc :VTC<CR>

" Help documentation
function! VimLLMHelp()
    echo "Vim LLM Teacher - Simplified"
    echo ""
    echo "Commands:"
    echo "  <leader>vt        - Ask for vim command (no context)"
    echo "  <leader>vtc       - Ask for vim command (with context)"
    echo "  :VT               - Interactive mode (no context)"
    echo "  :VT <query>       - Direct query (no context)"
    echo "  :VTC              - Interactive mode (with context)"
    echo "  :VTC <query>      - Direct query (with context)"
    echo "  :VimTeachModel    - Set LLM model (current: " . g:vim_llm_model . ")"
    echo ""
    echo "When a command is suggested:"
    echo "  1. Yes       - Execute the command"
    echo "  2. No        - Cancel"
    echo "  3. Register  - Copy command to register"
    echo "  4. ?         - Explain the vim concepts used"
    echo ""
    echo "Context lines: " . g:vim_llm_context_lines . " (change with let g:vim_llm_context_lines = N)"
endfunction

command! VimTeachHelp call VimLLMHelp()
command! VTHelp call VimLLMHelp()
