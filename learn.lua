--
-- OpenComputers Storage Drawers Controller (Minecraft 1.10.2)
-- by nzHook ( http://youtube.com/user/nzhook )
-- 08 April 2017
-- Released under a Creative Commons SA license
--
-- If given an argument search attached storage (storageside) for items and if 
--   one match pull upto 64 items into the attached chest (chestside)
--   If multiple items lists the items, give slot number to pull from that
--   slot
--   If no arguments return all items in chest (chestside)
--
-- Future updates will be available at http://youtube.com/user/nzhook
--
local c = require("component")
local shell = require("shell")
local sides = require("sides")
local serialization = require("serialization")
local filesystem = require("filesystem")

-- CHANGE THESE BASED ON YOUR SETUP
local craftertransposerid = c.get("fcb0f78b")
local learnertransposerid = c.get("d3859c73")
--local craftertransposerid = c.get("d3859c73")
local storageside = sides.left
--local chestside = sides.up
local crafterside = sides.up
local learnerside = sides.back
local learnerstorageside = sides.bottom
-- END CONFIG

-- Other config options
local folder = "/home/recipies"
-- End

if not craftertransposerid then
    print("Please give a valid crafter transposer address id, connected transposers are")
    for id, typ in pairs(c.list("transposer")) do
      print(id)
    end
    return
end
if not learnertransposerid then
    print("Please give a valid learner transposer address id, connected transposers are")
    for id, typ in pairs(c.list("transposer")) do
      print(id)
    end
    return
end

local st = c.proxy(craftertransposerid, "transposer")
if not st then
    print("What did you do with the crafting transposer with id " .. craftertransposerid .. "?")
    for id, typ in pairs(c.list("transposer")) do
      print(id)
    end
    return
end

local lt = c.proxy(learnertransposerid, "transposer")
if not lt then
    print("What did you do with the learner transposer with id " .. learnertransposerid .. "?")
    for id, typ in pairs(c.list("transposer")) do
      print(id)
    end
    return
end




--- Code from main script (needs to be removed)
local slots = {}
local maxslots = 0

local function refresher()
    status = "[ refreshing ]";
    local i = 0
    local u = 0
    local tmpslots = {}

    maxslots = st.getInventorySize(storageside)
    if not maxslots then
	maxslots = 0
	slots = {}
	print("[ NO INVENTORY ]")
	return
    end
    for i =1, maxslots do
      local item = st.getStackInSlot(storageside, i)
 
      if item then
	  u = u + 1
	  tmpslots[u] = {}
	  tmpslots[u].slot = i
          tmpslots[u].name = item.label
          tmpslots[u].id = item.name
          tmpslots[u].qty = item.size
          -- H O O K: HERE HERE
          tmpslots[u].dmg = item.damage
      end 

	-- For each item, force the system to check for events. passing 0 here should make it return straight away (im sure there used to be a better way)
--	event.pull(0, "nothinghere")
    end

    slots = tmpslots
	status = ""
end

--
--- end original code
--

if not filesystem.exists(folder) then
    filesystem.makeDirectory(folder)


    local tmpnew = {}
    tmpnew.id = "minecraft:sticks:0"
    tmpnew.recipe = {
      "minecraft:planks",
      nil,
      nil,
      
      "minecraft:planks",
      nil,
      nil,
    
      nil,
      nil,
      nil
    }
    tmpnew.exact = false
    tmpnew.qty = 4
    
    local f = io.open(folder .. "/" .. "minecraft_sticks_0", "w")
    local r = f:write(serialization.serialize(tmpnew))
    f:close()
end

local recipe = {}
local storerecipe = {}

-- Look at whats configured currently and send it back into storage
local counted = 0
for pti = 1, 9 do
  local i = lt.getStackInSlot(learnerside, pti)
  if i then
    print(i.name)
    recipe[pti] = i.name .. ":" .. i.damage
    storerecipe[pti] = i.name .. ":" .. i.damage
    counted = counted + 1
    lt.transferItem(learnerside, learnerstorageside, 1, pti)
  else
    recipe[pti] = nil
    storerecipe[pti] = nil
  end
end
if counted == 0 then
    print("I cannot see any items to use for the craft")
    return
end
refresher()



-- TODO Should be an arg?
local exact = true

local i = 0
local required = 0
local tofill = {}
local ptr = 0
for pti = 0, 9 do
  if recipe[pti] then
    required = required + 1
  end
end


-- We loop per slot as there will be more of them than required items
for i =1, #slots do
  for pti = 0, 9 do
    if recipe[pti] then
          if slots[i] and slots[i].qty > 0 and ((exact and slots[i].id .. ":" .. slots[i].dmg == recipe[pti]) or (not exact and slots[i].id == recipe[pti])) then
            print(i .. ": " .. slots[i].id .. " - " .. slots[i].name)
            
            tofill[pti] = slots[i].slot            
            slots[i].qty = slots[i].qty - 1
            recipe[pti] = nil       -- Dont try and fill it twice
            required = required - 1
          end
      end
    end
    if required == 0 then     -- No need to keep looping if we have everything
        break;
    end
end

-- If we have all the items we need then we can move them in now
--  We do this here for two reasons
--   1. If we dont have all the items we could make something not wanted
--   2. If we insert them all at once we dont need to do redstone magic to avoid weird crafting
if required == 0 then
  for pti = 1, 9 do
        if tofill[pti] then
          st.transferItem(storageside, crafterside, 1, tofill[pti], 10 - pti)
        end
  end

  -- Now we wait until something is returned
  local timeout = 30
  while not st.getStackInSlot(crafterside, 10) do
    print("Waiting")
    os.sleep(1)
    timeout = timeout - 1
    if timeout < 1 then
      break
    end
  end
  if timeout > 0 then
    local i = st.getStackInSlot(crafterside, 10)
    print(i.size .. " x " .. i.name)
  
    local tmpnew = {}
    tmpnew.id = i.name .. ":" .. i.damage
    tmpnew.recipe = storerecipe
    tmpnew.exact = exact
    tmpnew.qty = i.size
    
    local f = io.open(folder .. "/" .. string.gsub(i.name .. "_" .. i.damage, ":", "_"), "w")
    local r = f:write(serialization.serialize(tmpnew))
    f:close()
    
    st.transferItem(crafterside, storageside, 64, 10)
  else
    print("Timed out waiting for item")
  end
else
    print("?? Items were not stored")
    for pti = 0, 9 do
      if recipe[pti] then
        print(" - " .. recipe[pti])
      end
    end
end
