local c = require("component")
local ct = c.transposer
local sides = require("sides")
local event = require("event")
local computer = require("computer")
local serialization = require("serialization")

-- CHANGE THESE BASED ON YOUR SETUP
local refreshtime = 60
local storageside = sides.right
local chestside = sides.up
local ecside = sides.front
local ec_reserved_return = 5            -- The number of slots reserved for item return (in the WHOLE system)
local commsport = 125
-- END CONFIG

-- Check the sides are valid
if not ct.getInventorySize(ecside) then
	error("Invalid crafting ender chest side")
end
if not ct.getInventorySize(chestside) then
	error("Invalid player ender chest side")
end
if not ct.getInventorySize(storageside) then
	error("Invalid storage side")
end



-- Var init (these are global - see end)
slots = {}
freeslots = {}
maxslots = 0
usedslots = 0
status = ""
crafters = {}
currentcrafter = 1

local function storeitem(ct, chestside, storageside, i)
	local item = ct.getStackInSlot(chestside, i)
	if item then

		if not slots[item.name .. ":" .. item.damage] then
			makeslot(slots, item)
		end

		-- transfer to an existing slot, if none allow us to put the item then we select a new slot
		--   we go in reverse order as its likly the last one we used will be free, if its not
		--   then we can expend some energy to find the next free one
		--  TODO: Should we move the slot we find to the end?
		testslot = slots[item.name .. ":" .. item.damage].slots;

		local foundone = false
		for si = #testslot, 1, -1 do
			-- TODO: Should handle half filling here
			if ct.transferItem(chestside, storageside, 64, i, testslot[si]) then
				foundone = true
				break
			end
		end

		if not foundone then
			-- We dont care if we fill in a random order, so we just pop the last freeslot
			while not foundone do
				si = table.remove(freeslots)
				if not si then
					-- TODO: Need to handle when no more free slots exists (refresh)
					return
				end
				if ct.transferItem(chestside, storageside, 64, i, si) then
					table.insert(slots[item.name .. ":" .. item.damage].slots, si);
					foundone = true
					break
				end
			end
		end

		slots[item.name .. ":" .. item.damage].qty = slots[item.name .. ":" .. item.damage].qty + item.size
	end
end

-- RetrunCrafted, clears the result slots of the crafting chest
--   if given a slot will only do that slot
local function returncrafted(cmd, slot)
	if not slot then
		local ecslots = ct.getInventorySize(ecside)
		for i = ecslots - ec_reserved_return, ecslots do
			storeitem(ct, ecside, storageside, i)
		end
	else
		storeitem(ct, ecside, storageside, slot)
	end

--	computer.pushSignal("slotrefresh")
end


local function makeslot(inslots, item)
	inslots[item.name .. ":" .. item.damage] = {
		slots = {},
		name = item.label,
		id = item.name,
		dmg = item.damage,
		qty = 0
	}
end

local scanning = false
-- Refreher scans the inventory and updates the slot data
--  NOTE: This is possibly where most of the memory will go,
--    might need to limit it to the current page somehow?
function invrefresh()
    if scanning then
	return
    end
    returncrafted()

    status = "[ refreshing ]";
    local i = 0
    local u = 0
    local tmpslots = {}
    local tmpfreeslots = {}
    local nextwait = computer.uptime() + 1

    maxslots = ct.getInventorySize(storageside)
    if not maxslots then
	maxslots = 0
	slots = {}
	status = "[ NO INVENTORY ]"
	return
    end
    scanning = true
    for i =1, maxslots do
      local item = ct.getStackInSlot(storageside, i)
 
      if item then
	  if not tmpslots[item.name .. ":" .. item.damage] then
		makeslot(tmpslots, item)
	  end
	  table.insert(tmpslots[item.name .. ":" .. item.damage].slots, i);
	  tmpslots[item.name .. ":" .. item.damage].qty = tmpslots[item.name .. ":" .. item.damage].qty + item.size
	  usedslots = usedslots + 1
      else
	  -- in case we are looking at an inventory with 1000 or more free slots we only store the first 100 ('64k should be enough for anyone')
          --     if we get to no more free then we could run another refresh
	  table.insert(tmpfreeslots, i)
      end 

	-- While scanning wait 1 second every 2 seconds so we can process any other events
	if computer.uptime() > nextwait then
		event.pull(0, "nothinghere")
		nextwait = computer.uptime() + 1
	end
    end

    slots = tmpslots
    freeslots = tmpfreeslots
    scanning = false
    computer.pushSignal("itemsupdated")			-- Notify everything else that the items have changed
    status = ""
end

-- Grab a requested item and place it into the destination
--   currently item must be a slot number
--  @todo add support to do it by itemname instead
local function invget(cmd, item, qty)
	status = "[ Fetching ]"
	if not slots[item] then
		return
	end
	-- TODO Need to handle not having all of the items in the first slot
	ct.transferItem(storageside, chestside, qty, slots[item].slots[1])
	slots[item].qty = slots[item].qty - qty
	status = ""
--	if(slots[item].qty <= 0) then
--		computer.pushSignal("slotrefresh")
--	end
	computer.pushSignal("itemsupdated")			-- Notify everything else that the items have changed
end

-- Same again but for the crafters
local function ecget(cmd, item, qty)
	if not slots[item] then
		return
	end
	-- TODO Need to handle not having all of the items in the first slot
	ct.transferItem(storageside, ecside, qty, slots[item].slots[1])
	slots[item].qty = slots[item].qty - qty
	computer.pushSignal("itemsupdated")			-- Notify everything else that the items have changed
end

-- Returnthem Returns all items back to storage
local function returnthem()
	status = "[ Returning ]"
	for i = ct.getInventorySize(chestside), 1, -1 do
		storeitem(ct, chestside, storageside, i)
	end
	status = ""

	computer.pushSignal("itemsupdated")			-- Notify everything else that the items have changed
--	computer.pushSignal("slotrefresh")
end

local function newcrafter(null, addr, type)
	if not crafters[type] then
		crafters[type] = {}
	end
	for i =1, #crafters[type] do
		if crafters[type][i] == addr then
			return
		end
	end

	table.insert(crafters[type], addr)
end

local function itemlist(null, addr, max, searchfor)
        -- First sort the item list so its not in some random order
        local tmp = {}
        for k, v in pairs(slots) do
                if string.find(string.lower(slots[k].id .. "-" .. slots[k].name), string.lower(searchfor)) then
	                table.insert(tmp, k)
		end
        end
        table.sort(tmp, function(a, b) return slots[a].qty > slots[b].qty end )

	local rmsg = {
		maxslots = maxslots, 
		usedslots = usedslots, 
		items = {},
		searched = searchfor
	}
	local shown = 0
	for ignore, i in ipairs(tmp) do
                shown = shown + 1
                table.insert(rmsg["items"], {id = i, name = slots[i].name, qty = slots[i].qty})
                -- If we have reached the end of the page, skip the rest
                if shown > max then
                        break
                end
        end
	
	rmsg = serialization.serialize(rmsg);
	if addr then
		c.modem.send(addr, commsport, "itemslist", rmsg)
	else
		c.tunnel.send("itemslist", rmsg)
	end
end

-- note: c is already used for component
local function extmsg(null, src, dst, lport, null, cmd, a, b, c2, d, e, f) 
	if cmd == "itemlist" then
		if c.type(src) == "tunnel" then
			src = nil
		end
		computer.pushSignal(cmd, src, a, b, c2, d, e, f)
	else
		computer.pushSignal(cmd, a, b, c2, d, e, f)
	end
end


print("Doing initial scan of inventories...")
invrefresh()

print("REMINDER TO SELF: REfreshtimer is disabled");
--refreshtimer = event.timer(refreshtime, invrefresh, math.huge)
event.listen("slotrefresh", invrefresh)
event.listen("slotget", invget)
event.listen("slotecget", ecget)
event.listen("slotreturn", returnthem)
event.listen("craftreturn", returncrafted)
event.listen("crafterboot", newcrafter)
event.listen("itemlist", itemlist)

-- We can trigger a refresh using an event as well
-- computer.pushSignal("slotrefresh")


--event.cancel(refreshtimer)

-- Convert any inbound messages into local events
c.modem.open(commsport)
event.listen("modem_message", extmsg)


-- Register our vars into the global namespace for other scripts to access
_G.slots = slots
_G.maxslots = maxslots
_G.usedslots = usedslots

_G.crafters = crafters
_G.currentcrafter = currentcrafter
