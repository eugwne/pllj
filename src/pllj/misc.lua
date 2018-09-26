local function execute_list( list )
    for i = 1, #list do
        list[i][1](list[i][2])
    end
end



local Deferred = {}
Deferred.__index = Deferred
  
function Deferred:create()
    local d = {list = {}}
    setmetatable(d, Deferred)
    return d
end
  
function Deferred:add(item)
    table.insert(self.list, item)
end

function Deferred:call()
    execute_list(self.list)
end

return { 
    Deferred = Deferred,
 }