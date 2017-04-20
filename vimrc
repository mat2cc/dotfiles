execute pathogen#infect()

" Pathoden bundles installed
" - nerdcommenter
" - nerdtree
" - syntastic
" - ultisnips
" - vim-colors-solatized
" - vim-snippets

set nocompatible              " be iMproved, required
syntax enable
filetype plugin indent on     " required
set background=dark
colorscheme solarized

set showcmd   " display incomplete commands
set hlsearch  " highlight search matches

" Powerline
set  rtp+=/home/matthew/.local/lib/python2.7/site-packages/powerline/bindings/vim
set laststatus=2
set t_Co=256

set number 			      " show line numbers
set relativenumber 		" relative numbers 

inoremap jk <esc>

" Remaping muultiple screen movements keys
map <C-h> <C-w>h 
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l

" Disable arrow keys
noremap <Up> <Nop>
noremap <Down> <Nop>
noremap <Left> <Nop>
noremap <Right> <Nop>


" Tab spacing, 3 spaces
set tabstop=3
set shiftwidth=3
set softtabstop=3
set expandtab

" Syntiastic
autocmd FileType python if stridx(expand("%:p"), "/some/path/") == 0 |
        \ let b:syntastic_checkers = ["flake8"] | endif
let g:syntastic_cpp_compiler = 'g++'
let g:syntastic_cpp_compiler_options = ' -std=c++11 -stdlib=libc++ -pthraed'
let g:syntastic_cpp_checkers = ['clang_check']
let g:syntastic_cpp_check_header = 1
let g:syntastic_cpp_no_include_search = 1

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

" UltiSnips
let g:snips_author = 'Matthew Christofides'
let g:snips_email = 'matthewchristofides@gmail.com'
let g:snips_github = 'github.com/mat2cc'


let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" GUI settings
set guioptions-=m " remove menu bar
set guioptions-=T " remove tool bar
set guioptions-=r " remove scroll bar

" Fonts
set guifont=Consolas:h10:cDEFAULT

" Nerdtree
map <C-n> :NERDTreeToggle<CR>

" Nerdcommenter
let mapleader=","
let g:NERDSpaceDelims = 1
let g:NERDCompactSexyComs = 1
let g:NERDDefaultAlign = 'left'
let g:NERDCommentEmptyLines = 1
