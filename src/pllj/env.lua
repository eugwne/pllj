local spi = require("pllj.spi")
local NULL = require('ffi').NULL
local protect = require('pllj.misc').protect

--from http://lua-users.org/wiki/SandBoxes 

local _coroutine = {
    create = coroutine.create,
    resume = coroutine.resume,
    running = coroutine.running,
    status = coroutine.status,
    wrap = coroutine.wrap,
    yield = coroutine.yield,
}

local _math =
 {
    abs = math.abs,
    acos = math.acos,
    asin = math.asin,
    atan = math.atan,
    atan2 = math.atan2,
    ceil = math.ceil,
    cos = math.cos,
    cosh = math.cosh,
    deg = math.deg,
    exp = math.exp,
    floor = math.floor,
    fmod = math.fmod,
    frexp = math.frexp,
    huge = math.huge,
    ldexp = math.ldexp,
    log = math.log,
    log10 = math.log10,
    max = math.max,
    min = math.min,
    modf = math.modf,
    pi = math.pi,
    pow = math.pow,
    rad = math.rad,
    --math.random - SAFE (mostly) - but note that returned numbers are pseudorandom, and calls to this function affect subsequent calls. This may have statistical implications.
--math.randomseed - UNSAFE (maybe) - see math.random
    sin = math.sin,
    sinh = math.sinh,
    sqrt = math.sqrt,
    tan = math.tan,
    tanh = math.tanh,
 }

 local _string = {
    byte = string.byte,
    char = string.char,
    --string.dump - UNSAFE (potentially) - allows seeing implementation of functions.
    find = string.find, -- warning: a number of functions like this can still lock up the CPU [6]
    format = string.format,
    gmatch = string.gmatch,
    gsub = string.gsub,
    len = string.len,
    lower = string.lower,
    match = string.match,
    rep = string.rep,
    reverse = string.reverse,
    sub = string.sub,
    upper = string.upper,
 }

 local _table = {
    insert = table.insert,
    maxn = table.maxn,
    remove = table.remove,
    sort =table.sort,
 }

 local _os = {
    clock = os.clock,
    difftime = os.difftime,
    time = os.time
 }

local box = { 
    spi = spi, 
    NULL = NULL,
    print = print, 

    assert =  assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    pcall = subt_pcall,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    unpack = unpack,
    --xpcall = xpcall, subt?

    coroutine = protect(_coroutine),
    math = protect(_math),
    string = protect(_string),
    table = protect(_table),
    os = protect(_os),
}

local env_mt = {
    __index = box,
    __newindex = function (self, var,  ... )
        return error(string.format( "attempt to set global var '%s'", var))
    end
}
local env = {}
setmetatable(env, env_mt)

return {
    env = env,
    box = box,
}