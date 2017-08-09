local fs = require("filesystem")
local serialization = require("serialization")
local computer = require("computer")
local component = require("component")
local shell = require("shell")

local plan = false			-- Show the plan vs do the plan (setting to true will tru and craft everything at once)
plan = true
local folder = "/home/bios/recipies"


if not crafters or not crafters["craft"] then
	error("No crafters found? - maybe they need a kick")
end


local args, opts = shell.parse(...)

if not args[1] then
    print("Please give me something to do")
    return
end

local letsmake = args[1]



local function iname(item)
	return item.id .. ":" .. item.dmg
end

-- Load recipies
local rec= {}
for file in fs.list(folder) do
	local f = io.open(folder .. "/" .. file, "r")
	local r = serialization.unserialize(f:read("*all"))
	f:close()
	if r then
		rec[r.id] = r
	else
		print("WARNING: " .. file .. " could not be understood")
	end
end

if(not rec[letsmake]) then
	print("Could not find " .. letsmake)
	os.exit()
end


-- work out what we are making
local inuse = {}				-- # of items that are inuse (crafted or in storage)
local crafted = {}				-- # of items that need to be crafted
local levels = {}				-- Higher levels, indicate items further into a craft so need to done first
local missing = {}				-- # of items that are missing
local havemissing = false			-- Flag for if missing has anything (saves doing a loop)

local function buildreq(r, l)
	-- If we dont have the items and there is no way to make it then we can stop here
	if(not slots[r] and not rec[r]) then
		if(not missing[r]) then
			missing[r] = 0
		end
		missing[r] = missing[r] + 1
		havemissing = true
		return 0
	end

	-- Set the reqs to 0 so we can use them in calcs
	if(not crafted[r]) then
		crafted[r] = 0
	end
	if(not slots[r]) then
		slots[r] = {qty = 0}
	end
	if(not inuse[r]) then
		inuse[r] = 0
	end

	if((slots[r].qty + crafted[r]) - inuse[r] > 0) then
		inuse[r] = inuse[r] + 1
		return 1
	end
	if(not rec[r] and (slots[r].qty + crafted[r]) - inuse[r] <= 0) then
		if(not missing[r]) then
			missing[r] = 0
		end
		missing[r] = missing[r] + 1
		havemissing = true
		return 0
	end

	levels[r] = {r, l}
	for k, i in pairs(rec[r].recipe) do
		buildreq(i, l + 1)
	end
	crafted[r] = crafted[r] + rec[r].qty
	inuse[r] = inuse[r] + 1
end


buildreq(letsmake, 0)
print("Will use:")
for k, i in pairs(inuse) do
	if inuse[k] > 0 then
		print(k .. "=" .. inuse[k])
	end
end

if havemissing then
	print("")
	print("Missing items prevent the craft:")
	for k, i in pairs(missing) do
		print(k .. "=" .. missing[k])
	end
else
	local inuse = {}			-- Tracking local usage

	print("")
	print("To craft:")
	local tmp = {}
	for k, v in pairs(levels) do
		table.insert(tmp, v)
	end
	table.sort(tmp, function(a, b) return a[2] < b[2] end )


	-- Wait while there are things to craft
	--  @todo Should do this in the background
	local havecraft = true
	while havecraft do
		havecraft = false
		for n, i in ipairs(tmp) do
			k = i[1]
			if crafted[k] > 0 and ((not clevel or clevel == levels[k][2]) or plan) then
				havecraft = true

				-- Do we have enough now to make this item?
				local testi = {}
				local canmake = math.ceil(crafted[k] / rec[k].qty)
				local sendr = ""
				for rk, ri in pairs(rec[k].recipe) do
					if(not testi[ri]) then
						testi[ri] = 0
					end
					if(not inuse[ri]) then
						inuse[ri] = 0
					end
					testi[ri] = testi[ri] + 1
					sendr = sendr .. ri .. ","
				end
				for rk, ri in pairs(testi) do
					if canmake > math.ceil(math.floor((slots[rk].qty - inuse[rk]) / ri) / rec[k].qty) then
						canmake = math.ceil(math.floor((slots[rk].qty - inuse[rk]) / ri) / rec[k].qty)
					end
				end

				if canmake > 0 or plan then
					print("Crafting " .. canmake .. " / " .. crafted[k] .. " x " .. k .. " (prio " .. levels[k][2] .. ")")
				end
				if canmake > 0 then
			
					-- pick the next available crafter
					local sendto = crafters["craft"][currentcrafter]
					currentcrafter = currentcrafter + 1
					if currentcrafter >= #crafters then
						currentcrafter = 1
					end

					-- Yay, we have some items and somewhere to craft. Request them to be moved to crafting storage.
					--   we track what we use here so we can continue the loop, this may mean we are slightly off but should be fine
					--   better than trying to overcraft with things that are not here yet
					for rk, ri in pairs(testi) do
						computer.pushSignal("slotecget", rk, ri * canmake)
						inuse[rk] = inuse[rk] + (ri * canmake)
					end

					component.modem.open(125)
					component.modem.send(sendto, 125, "docraft", k, canmake, sendr)
					component.modem.close(125)

					crafted[k] = crafted[k] - canmake * rec[k].qty

					-- Dont try and craft anything lower on this pass
					clevel = levels[k][2]
				end
			end

		end
		os.sleep(5)
	end
	print("Waiting for final item...")
	while not slots[letsmake] or not letsmake do os.sleep(1); end
	computer.pushSignal("slotget", letsmake, 1)
end
