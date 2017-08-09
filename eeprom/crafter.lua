local ec_side = 1			-- The # side the enderchest is on (1 = top)
local ec_reserved_return = 5		-- The number of slots reserved for item return (in the WHOLE system)
--local m_return_slot = 4			-- The slot the connected machine outputs to (normally last)
local m_return_slot = 10			-- The slot the connected machine outputs to (normally last)
local dbg_port = 124
local comms_port = 125

-- We open the modem here so we can send messages for display back to the master
--   dont really need this its just for debugging
local modem = component.list("modem")()
if not modem then error("No modem/network found") end
modem = component.proxy(modem)
if not modem then error("Error loading modem") end

print = function(text)
	modem.broadcast(dbg_port, text)
end

print(computer.address() .. " is booting")
-- End debug message setup

-- Tell everyone we are here (dont know who the master is)
modem.broadcast(comms_port, "crafterboot", modem.address, "craft")

local transposer = component.list("transposer")()
if not transposer then	error("No transposer found") end

tc = component.proxy(transposer)

maxslots = tc.getInventorySize(ec_side)
if not maxslots then error("Please place ender chest side " .. ec_side) end

local function iname(item) 
	return item.name .. ":" .. item.damage
end

local function pullitem(getitem, qty, intoside, intoslot)
	if not getitem then return; end
	for i = 1, maxslots - ec_reserved_return - 1 do
		local item = tc.getStackInSlot(ec_side, i)

		if item and iname(item) == getitem then
--print(intoslot .. " = " .. iname(item))
			if tc.transferItem(ec_side, intoside, qty, i, intoslot) then
				print("Moved " .. iname(item) .. " from ec slot " .. i .. " into side " .. intoside .. ":" .. intoslot)
				return
			else
				print("FAILED Moving " .. iname(item) .. " from ec slot " .. i .. " into side " .. intoside .. ":" .. intoslot)
			end
		end 
	end
	print("Failed to find " .. getitem)
end

local function modem_message(a,b,c,e,f,g,h,i,j)
	--  a      b        c     d    e     f     g      h    i     j
	-- null, msgfrom, null, null, null, null, msg, making, qty, rec
	if g == "docraft" then
		for s = 0, 5 do
			-- we assume if slot 1 has an item then its in-use. Need a better way here
			if s ~= ec_side and tc.getInventorySize(s) and not tc.getStackInSlot(s, 1) then
				print("Selecting machine on side " .. s .. " for " .. h)
				local fi = 1
				for kk in string.gmatch(j, "[^,]+") do
					pullitem(kk, i, s, fi); 
					fi = fi + 1
				end
				return
			end
		end
		print("No machines are available for " .. h)
		-- Nothing is available, return a failure
		modem.send(b, comms_port, "fail", h)
		return
	end
end

-- Wait for an event, if its a message process the message then return
local function eventwait(tmot)
	local til = computer.uptime() + tmot
	while computer.uptime() < til do
		local a,b,c,e,f,g,h,i,j = computer.pullSignal(1)
		if a == "modem_message" then
			modem_message(a,b,c,e,f,g,h,i,j)
		end
	end
end

-- Searches for a free return slot, moves all the item into it and sends the return cmd
--   will wait until a slot is free
local fullwaiter = 1
local function returnitem(fromside, fromslot, waititem)
	for i = maxslots - ec_reserved_return, maxslots do
		local item = tc.getStackInSlot(ec_side, i)
		if not item or iname(item) == waititem then
			if tc.transferItem(fromside, ec_side, 64, fromslot, i) then
				print("Returned item from side " .. fromside .. ":" .. fromslot .. " to ec slot " .. i)
				modem.broadcast(comms_port, "craftreturn", i)
				fullwaiter = 1
				return
			else
				print("FAILED Returning " .. waititem .. " to ec slot " .. i)
			end
		end
	end
	if fullwaiter < 300 then			-- If there is no space, back off slowly
		fullwaiter = fullwaiter + 1
	end
	print("No space to return " .. waititem .. ", now at " .. fullwaiter .. " seconds")
end

modem.open(comms_port)

-- We loop until we have something to do
while true do
	local s
	for s = 0, 5 do
		if s ~= ec_side and tc.getInventorySize(s) then			-- Ignore the enderchest side
			local w = tc.getStackInSlot(s, m_return_slot)
			if w then returnitem(s, m_return_slot, iname(w)) end
		end
	end

	eventwait(fullwaiter)
end
