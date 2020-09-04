# pllj [![Build Status](https://travis-ci.org/eugwne/pllj.svg?branch=master)](https://travis-ci.org/eugwne/pllj)
LuaJIT(2.1) FFI PostgreSQL language extension 

Examples: see sql folder

How to build: 

Use artifact with generated FFI: 
make && sudo make install && sudo make install-module && make installcheck

How to build and generate FFI: 

see .travis.yml 

FFI wrappers(api_...) are generated with a gcc plugin from gen/gen.c (see .travis.yml)

