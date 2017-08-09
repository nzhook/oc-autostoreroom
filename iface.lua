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
--local ct = c.transposer
local sides = require("sides")
local event = require("event")
local term = require("term")
local computer = require("computer")
local serialization = require("serialization")
local gpu = c.gpu
local modem

-- MISC CONFIG
local commsport = 125
local screensaveractivate = 120
-- END CONFIG

-- Var init
local page = 0
local onpage = {}
local doloop = true
local w, h = 0
local letterpad = ""
local searchfor = ""
-- Setting this to 0 will start with the itemlist
--local screensavertimer = 300
local screensavertimer = 0
local qtyselector = nil
local delgado = nil

-- Global for things to update the display
_G.status = ""


if c.isAvailable("modem") then
	modem = c.modem
	modem.open(commsport)
	print("Using modem card")
else
	modem = c.tunnel
	print("Using link card")
end

-- Comms are done via a linked card OR a modem but both have differing command sets
local function comms(c1, c2, c3, c4, c5, c6) 
	if modem.type == "tunnel" then
		modem.send(c1, c2, c3, c4, c5, c6)
	else
		if delgado then
			modem.send(delgado, commsport, c1, c2, c3, c4, c5, c6)
		else
			modem.broadcast(commsport, c1, c2, c3, c4, c5, c6)
		end
	end
end

-- We have to have a screensaver, dont we?
do
-- quick script to write chars to the term without spaces
local function gpuprint(y, x, text)
	for i = 1, string.len(text) do
		if string.sub(text, i, i) ~= " " then
			gpu.set(y + i, x, string.sub(text, i, i))
		end
	end
end

local ssstate = 0
function screensaver() 
	if screensavertimer < screensaveractivate then
		screensavertimer = screensavertimer + 1
		return
	end
	-- Once we get here, we use screensavertimer as a flag so we can clear the terminal once
	if screensavertimer < 3600 then
		term.clear()
	end
	screensavertimer = 3600

	if component.table then
		-- Would be nice to have a active/inactive state
		return
	end


	local prefix = ""

	w, h = term.getViewport()

	local sh = (h / 2) - (12 / 2)
	local sw = (w / 2) - (28 / 2)


	term.setCursor(1, sh)
	gpu.setForeground(0xff0000, false)

	local prefix = string.rep(" ", sw - 1)
	local prefix1 = prefix
	if ssstate == 0 then
		ssstate = 1
		prefix1 = prefix .. " "
		print(prefix .. "                                     ");  
	else
		ssstate = 0
	end

--                       123456789 123456789 123456789 123456789 123
	print(prefix1 .. "              )     )      )      )  ");  
	print(prefix1 .. "           ( /(  ( /(   ( /(   ( /(  ");  
	print(prefix1 .. "           )\\()) )\\())  )\\())  )\\())  "); 
	print(prefix1 .. "  (    (  (( )\\ (( )\\  (( )\\  (( )\\  ");  
	print(prefix1 .. "  )\\ ) )\\   (( )  (( )   (( )   (( )  "); 
	print(prefix1 .. "  ( /((( )                             ");  
	print(prefix1 .. "     )     ");   
	print(prefix1 .. "        ");   

	gpu.setForeground(0xffffff, false)
	gpuprint(sw, sh + 5, "           _  _     _      _  _   _  "); 
	gpuprint(sw, sh + 6, " _ _    _ | || | / _ \\  / _ \\| |/ / ");  
	gpuprint(sw, sh + 7, "| ' \\ |_ /| __ || (_) || (_) | ' < ");   
	gpuprint(sw, sh + 8, "|_||_|/__||_||_| \\___/  \\___/ _|\\_\\ ");

	term.setCursor(1, sh + 10)
	print(prefix .. "  " .. usedslots .. " of " .. maxslots .. " used     ")
	local perc = (usedslots / (maxslots+0.0001))
	print(prefix .. "  [" .. string.rep("-", perc * 30) .. string.rep(" ", 30 - (perc * 30)) .. "] ")
end
end


-- Display Displays the slot data
local function display() 
	-- Dont display anything if the screensaver is active
	if screensavertimer > screensaveractivate then
		return
	end

	w, h = term.getViewport()
	term.setCursor(1, 1)
	print("X" .. string.rep("=", 5) .. "__RETURN__" .. string.rep("=", w- (6+10)))
	local i = 0
	local shown = 0
	for i, ignore in ipairs(slots) do
		local descr = slots[i].id .. " - " .. slots[i].name  .. " (" .. slots[i].qty .. ")"
		print(descr .. string.rep(" ", w - string.len(descr)))
		shown = shown + 1
		onpage[shown] = i
	end
	-- Clear the remainder
        for i = shown + 1, h -4 do
		print(string.rep(" ", w))
		onpage[i] = nil
	end

	term.setCursor(1, h-3)
	print("====[ " .. searchfor .. string.rep(" ", w - (string.len(searchfor) + 6 + 6)) .. " ]====")
	-- letterpad is used by touchy to work out what was pressed
	letterpad = " ABCDEFGHIJKLMNOPQRSTUVWXYZ   0123456789                                  ^:- <"
	print(letterpad)
	print(string.rep("=", w))

	if status then
		term.setCursor(w - 15, 1)
		print(status)
	end


	if qtyselector then
		local sel = "[ 1]"
		if qtyselector.qty >= 10 then
			sel = sel .. " [10]"
		else
			sel = sel .. "     "
		end
		if qtyselector.qty >= 32 then
			sel = sel .. " [32]"
		else
			sel = sel .. "     "
		end
		if qtyselector.qty >= 64 then
			sel = sel .. " [64]"
		else
			-- TODO: We should allow requesting the remaining
			sel = sel .. "     "
		end
		sel = " " .. sel .. " "

		if string.len(sel) < 15 then
			sel = string.rep(" ", (15 - math.floor(string.len(sel)) / 2)) .. sel .. string.rep(" ", (15 - math.floor(string.len(sel)) / 2))
		end

		local hline = math.floor(h / 2)
		local disp = qtyselector.name
		if string.len(disp) < string.len(sel) then
			disp = string.rep(" ", (string.len(sel) - math.floor(string.len(disp)) / 2)) .. disp .. string.rep(" ", (string.len(sel) - math.floor(string.len(disp)) / 2))
		end
		local selsize = math.floor(string.len(disp) / 2)

		gpu.setBackground(0x0000ff, false)
		term.setCursor((w / 2) - selsize, hline - 3)
		print("  " .. string.rep(" ", string.len(disp))  .. "  ")
		term.setCursor((w / 2) - selsize, hline - 2)
		print("  " .. disp  .. "  ")

		term.setCursor((w / 2) - selsize, hline - 1)
		print("  " .. string.rep(" ", string.len(disp))  .. "  ")
		term.setCursor((w / 2) - selsize, hline)
		print("  " .. string.rep(" ", string.len(disp))  .. "  ")
		term.setCursor((w / 2) - selsize, hline + 1)
		print("  " .. string.rep(" ", string.len(disp))  .. "  ")
		term.setCursor((w / 2) - selsize, hline + 2)
		print("  " .. string.rep(" ", string.len(disp))  .. "  ")

		selsize = math.floor(string.len(sel) / 2)
		term.setCursor((w / 2) - selsize, hline - 1)
		print(" +" .. string.rep("-", string.len(sel)) .. "+ ")
		term.setCursor((w / 2) - selsize, hline)
		print(" |" .. sel .. "| ")
		term.setCursor((w / 2) - selsize, hline + 1)
		print(" +" .. string.rep("-", string.len(sel)) .. "+ ")

		qtyselector.yline = hline
		qtyselector.xline = (w / 2) - selsize
	end
	gpu.setBackground(0x000000, false)
end

-- Touchy takes care of when someone presseses a button
--   or item
local function touchy(null, null, x, y)
	if screensavertimer >= 3600 then
		screensavertimer = 0
		display()
		return
	end
	screensavertimer = 0

	-- If you hit the special place it will exit the program (BUG: Does not seem to work while refreshing)
	if y == 1 and x == 1 then
		term.clear()
		print("You hit me!")
		computer.pushSignal("wedontwanttoreturn")
		doloop = false
		return
	end

	-- Hitting the top line will send everything back
	if y == 1 and x > 6 and x < 17 then
		comms("slotreturn")
--		computer.pushSignal("slotreturn")
		return
	end

	-- If the qty selector is up then we may need to check for a qty selection
	--     we make sure yline is setup before looking for it
	if qtyselector and qtyselector.yline then
		if y == qtyselector.yline then
			local clicked = (x - qtyselector.xline) / 5
			if math.floor(clicked) == math.floor(clicked + 0.2) then			-- Over 8 is the seperator
				clicked = math.floor(clicked)
				if clicked == 1 then
					size = 1
				end
				if clicked == 2 then
					size = 10
				end
				if clicked == 3 then
					size = 32
				end
				if clicked == 4 then
					size = 64
				end
				if size then
					comms("slotget", slots[qtyselector.inslot].id, size)
--					computer.pushSignal("slotget", qtyselector.inslot, size)
--					ct.transferItem(storageside, chestside, size, qtyselector.slot)
--					slots[qtyselector.inslot].qty = slots[qtyselector.inslot].qty - size
	 				qtyselector = nil
				end
			end


			display()
			-- Dont pass the touch thru
			return
		else
			if y > qtyselector.yline - 4 and y < qtyselector.yline + 3 then
				-- Selecting inside the box does nothing
				return
			end

			-- Clicking anywhere closes the box
			qtyselector = nil
			display()
			return
		end
	end

	-- 4 line from the bottom should be the letters
	if y == (h - 2) then
		local cc = string.sub(letterpad, x, x)
		if cc == "<" then
			if string.len(searchfor) > 1 then
				searchfor = string.sub(searchfor, 1, string.len(searchfor) - 1)
			else
				searchfor = ""
			end
		else
			searchfor = searchfor .. cc
		end
		comms("itemlist", h - 5, searchfor)
		display()
	else
		-- Look for a slot
		if y >= 2 and y < h -2 then
			if onpage[y - 1] and slots[onpage[y - 1]] then
				print(" ==== " .. slots[onpage[y - 1]].name)
				qtyselector = slots[onpage[y - 1]]
				qtyselector.inslot = onpage[y - 1]
				display()
			else
				print("no?", y - 1, onpage[y - 1])
			end
		end
	end
end

local function key_up(null, null, ascii)
	if ascii == 8 then
		if string.len(searchfor) > 1 then
			searchfor = string.sub(searchfor, 1, string.len(searchfor) - 1)
		else
			searchfor = ""
		end
	elseif (ascii >= 32 and ascii <= 126) then
		screensavertimer = 0
		searchfor = searchfor .. string.upper(string.char(ascii))
	end
	comms("itemlist", h - 5, searchfor)
	display()
end


local function itemslist(msg) 
	local tmp = serialization.unserialize(msg);
	maxslots = tmp.maxslots
	usedslots = tmp.usedslots
	slots = tmp.items
--	display()
end

local function extmsg(tst, src, dst, lport, null, cmd, a, b, c2, d, e, f) 
	if cmd == "itemslist" then
		itemslist(a)
		return
	end
	print(cmd .. " is unknown?")
end

-- Otherwise we just wait around and every now and then refresh the storage
--local e = {event.pullFiltered(filter)}

-- Send out a request for item data, this will set up the first page
--  the screensaver data and let us identify the master
print("Searching for Delgado...")
w, h = term.getViewport()
while not delgado do
	comms("itemlist", h - 5, "")
	
	-- Would be less power hugry if we could call event.pull(5, "modem_message") but a tunnel event is nil so it never returns??
	local e, null, src, null, null, cmd, a  = event.pull(5)
	if(cmd == "itemslist") then
		delgado = src
		itemslist(a)
	end
end

event.listen("modem_message", extmsg)
event.listen("touch", touchy)
event.listen("key_up", key_up)
event.listen("itemsupdated", display)

-- Tablets dont have this function
if c.screen.setTouchModeInverted then
	c.screen.setTouchModeInverted(true)
end

term.clear()
screensaver()
local sstimer = event.timer(1, screensaver, math.huge)
while doloop do
	display()

	-- Every now and then we want to update the display, but it should be rare
	local e = event.pull(10, "wedontwanttoreturn")
end
event.ignore("touch", touchy)
event.ignore("key_up", key_up)
event.ignore("itemsupdated", display)
event.ignore("modem_message", extmsg)
event.cancel(sstimer)

if c.screen.setTouchModeInverted then
	c.screen.setTouchModeInverted(false)
end
