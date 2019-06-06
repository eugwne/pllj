#!/bin/sh


setup_git() {
  git config --global user.email "travis@travis-ci.org"
  git config --global user.name "Travis CI"
}

commit_website_files() {
  git checkout -b $PGVERSION
  git add src/pllj/pg/i.lua
  git commit --message "Travis build: $TRAVIS_BUILD_NUMBER [ci skip]"
}

upload_files() {
  echo "upload..." 
  git remote rm origin
  git remote add origin https://eugwne:${SOMEVAR}@github.com/eugwne/pllj.git > /dev/null 2>&1
  git push -f -u origin $PGVERSION >/dev/null 2>&1
}

if [ "$TRAVIS_BRANCH" == "master" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
  setup_git
  commit_website_files
  upload_files
fi
