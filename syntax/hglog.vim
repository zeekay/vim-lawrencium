" Vim syntax file
" Language:     hg log output
" Maintainer:   Ludovic Chabant <ludovic@chabant.com>
" Filenames:    ^hg-log-*.txt

if exists("b:current_syntax")
    finish
endif

syn case match

syn match hglogChangeset            "changeset: .*"
syn match hglogDiffstatFilename     "\v^ [^|]+" contained
syn match hglogDiffstatInsertion    "\v[+]+" contained
syn match hglogDiffstatDeletion     "\v[-]+" contained
syn match hglogDiffstatModified     "\v^ .+\|\s+\d+\s+.*$" contains=hglogDiffstatFilename,hglogDiffstatInsertion,hglogDiffstatDeletion

hi def link hglogChangeset          Identifier
hi def link hglogDiffstatFilename   Constant
hi def link hglogDiffstatInsertion  Statement
hi def link hglogDiffstatDeletion   Keyword
