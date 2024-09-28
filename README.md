# Deploy Laravel applications using bash

### usage

on your local machine
- `git clone git@github.com:mokhosh/laravel-sheploy.git`
- `cd laravel-sheploy`
- `./sheploy.sh`

this will copy the repo on your server, and ssh into it
- `cd ~/laravel-sheploy`
- `./setup.sh`

### todo
- [x] do any step you want
- [ ] cleanup after installing typesense
- [ ] update typesense key from config if installed
- [ ] dont change env db if mysql is not installed
- [ ] put blank lines before prompts
- [ ] stylize prompts
- [ ] modularize
- [ ] beautify output and input
- [ ] get the ssh port from input
- [ ] get the ssh user from input
- [ ] ask to create ssh key if it doesnt exist
- [ ] find a way to keep ssh alive after EOF so we run ssh once
