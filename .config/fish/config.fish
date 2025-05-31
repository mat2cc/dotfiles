pyenv init - fish | source

alias ls eza
alias l "eza -lah --icons"
alias vi nvim
alias vim nvim

alias gs "git status"
alias gl "git log"

alias git-recent "git branch --sort=-committerdate"

alias flush_dns "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

alias aws-us-new-account "aws-vault exec prod-us --"
alias aws-us "aws-vault exec prod-us-old --"
alias aws-us-admin "aws-vault exec prod-us-admin --"
alias aws-new-staging "aws-vault exec new-staging --"

alias docker-login "aws ecr get-login-password | docker login --username AWS --password-stdin 189785257069.dkr.ecr.us-east-1.amazonaws.com"
