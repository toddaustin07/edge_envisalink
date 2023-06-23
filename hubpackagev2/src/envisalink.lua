--[[
  Copyright 2021 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  Samsung SmartThings Edge Driver for Envisalink - module to (1) handle incoming Envisalink messages, (2) create
  json tables & log messages based on them, and (3) send commands to Envisalink

  ** The Envisalink message-parsing code here is ported from the alarmserver Python package
  originally developed by donnyk+envisalink@gmail.com, which also included subsequent modifications/enhancements by
  leaberry@gmail.com, jordan@xeron.cc, and ralphtorchia1@gmail.com

--]]


local evl = require "envisalinkdefs"
local log = require "log"

local cosock = require "cosock"
local socket = require "cosock.socket"

-- Constants
local MAXPARTITIONS = 4
local MAXZONES = 16
local MAXEVENTS = 10
local MAXALLEVENTS = 100
local MAXALARMUSERS = 10
local TIMETOWAIT = 2

-- Module variables
local devhandler
local clientsock
local connected = false
local loggedin = false
local reconnect_timer


local function getMessageType(code)
	return evl.ResponseTypes[code]
end

local function to_chars(instr)
	chars = {}
	for c in string.gmatch(instr, ".") do
		table.insert(chars, string.byte(c))
	end
	return chars
end

local function get_checksum(code, data)
	local sum = 0
	
	for _, x in ipairs(to_chars(code)) do
		sum = sum + x
	end
	for _, x in ipairs(to_chars(data)) do
		sum = sum + x
	end
	
	return string.sub(string.format('%02X', sum), -2)
end

local msghandler			-- forward reference to msghandler function

local function connect()

	local listen_ip = "0.0.0.0"
	local listen_port = 0

	local client = assert(socket.tcp(), "create LAN socket")

	assert(client:bind(listen_ip, listen_port), "LAN socket setsockname")

	local ret, msg = client:connect(conf.envisalink.ip, conf.envisalink.port)
	
	if ret == nil then
		log.error ('Could not connect to EnvisaLink:', msg)
		client:close()
	else
		client:settimeout(0)
		connected = true
		clientsock = client
		evlDriver:register_channel_handler(client, msghandler, 'LAN client handler')
		return client
	end
end


local function disconnect()

	connected = false
	loggedin = false
	
  if timers.reconnect then
		evlDriver:cancel_timer(timers.reconnect)
	end
	if timers.waitlogin then
		evlDriver:cancel_timer(timers.waitlogin)
	end
	timers.reconnect = nil
	socket.sleep(.1)
	timers.waitlogin = nil
	
	if clientsock then
		evlDriver:unregister_channel_handler(clientsock)
		clientsock:close()
	end
	devhandler.onoffline('offline')

end

local doreconnect						-- Forward reference

-- This function invoked by delayed timer
local function dowaitlogin()
	
	timers.waitlogin = nil
	if not loggedin then
		log.warn('Failed to log into Envisalink; connect retry in 15 seconds')
		disconnect()
		timers.reconnect = evlDriver:call_with_delay(15, doreconnect, 'Re-connect timer')
	else
		devhandler.onoffline('online')
	end
end

-- This function invoked by delayed timer
doreconnect = function()

	log.info ('Attempting to reconnect to EnvisaLink')
	timers.reconnect = nil
	local client = connect()
	
	if client then
	
		log.info ('Re-connected to Envisalink')
		
		timers.waitlogin = evlDriver:call_with_delay(3, dowaitlogin, 'Wait for Login')
		
	else
		timers.reconnect = evlDriver:call_with_delay(15, doreconnect, 'Re-connect timer')
	end
end

		
local function send_command(code, data, checksum, force)

	if loggedin or force then

		local to_send
		
		if checksum == nil then; checksum = true; end

		if checksum == true then
			to_send = code .. data .. get_checksum(code, data) .. '\r\n'
		else
			to_send = code .. data .. '\r\n'
		end
		
		log.debug ('TX > ' .. to_send)
		
		clientsock:send(to_send)
		
	else
		if not connected then
			log.warn ('Cannot send commands to Envisalink: not connected')
		else
			log.warn ('Cannot send commands to Envisalink: not logged in')
		end
	end
	
end


local function bin(x)
	local ret = ''
	while x ~= 1 and x ~= 0 do
		ret = tostring(x%2) .. ret
		x=math.modf(x/2)
	end
	ret = tostring(x) .. ret
	
	return string.format('%08d', ret)
end


local function ends_with(str, ending)

	return ending == "" or str:sub(-#ending) == ending
	
end


local function build_event_table(code, parameters, event, message)

	local update = {}

	if evl.ResponseTypes[code] then
	
		if code == 620 then
			update =	{
									['type'] = 'partition',
									['value'] = '1',
									['status'] = 'duress'
								}
		elseif code == 616 then
			update =	{
									['type'] = 'bypass',
									['status'] = 'bypass',
									['parameters'] = {}
								}
								
			local index = 1
			local count = 9
			local binary = bin(tonumber(tostring(parameters:sub(index, index+1)),16))

			for zone = 1, MAXZONES do
				if count < 2 then
					count = 9
					index = index + 2
					binary = bin(tonumber(tostring(parameters:sub(index, index+1)),16))
				end
				
				count = count-1
				
				if conf.zones[zone] then
					if conf.zones[zone].name then
						local value
						if binary:sub(count,count) == '1' then
							value = 'on'
						else
							value = 'off'
						end
						update['parameters'][tostring(zone)] = value
					end
				end
			end
		
		elseif (code == 510) or (code == 511) then
		
			local codeMap = { [510] = 'led', [511] = 'ledflash' }
			
			local ledMap = { 'backlight', 'fire', 'program', 'trouble', 'bypass', 'memory', 'armed', 'ready' }
											
			update =  {
									['type'] = 'partition',
									['value'] = '1',
									['status'] = codeMap[code],
									['parameters'] = {}
								}
								
			local binary = bin(tonumber(tostring(parameters), 16))
			
			for i = 1, 8 do
				if binary:sub(i,i) == '1' then
					value = 'on'
				else
					value = 'off'
				end
				update['parameters'][ledMap[i]] = value
			end
		
		elseif event.type == 'system' then
		
			local codeMap = {
												[621] = 'keyfirealarm',
												[622] = 'keyfirerestore',
												[623] = 'keyauxalarm',
												[624] = 'keyauxrestore',
												[625] = 'keypanicalarm',
												[626] = 'keypanicsrestore'
											}
			update = 	{
									['type'] = 'partition',
									['value'] = '1',
									['status'] = codeMap[code]
								}
								
		elseif event.type == 'partition' then
			
			local partnum = tonumber(parameters:sub(1,1))
			if conf.partitions[partnum] then
				if code == 655 then
					send_command('071', '1*1#')						-- WHY????
				end
				
				local codeMap = {
													[650] = 'ready',
													[651] = 'notready',
													[653] = 'forceready',
													[654] = 'alarm',
													[655] = 'disarm',
													[656] = 'exitdelay',
													[657] = 'entrydelay',
													[663] = 'chime',
													[664] = 'nochime',
													[701] = 'armed',
													[702] = 'armed',
													[840] = 'trouble',
													[841] = 'restore'
												}
				update =  {
										['type'] = 'partition',
										['name'] = conf.partitions[partnum],
										['value'] = tostring(partnum)
									}
									
				if code == 652 then
					if ends_with(message,'Zero Entry Away') then
						update['status'] = 'instantaway'
					elseif ends_with(message,'Zero Entry Stay') then
						update['status'] = 'instantstay'
					elseif ends_with(message,'Away') then
						update['status'] = 'away'
					elseif ends_with(message,'Stay') then
						update['status'] = 'stay'	
					else
						update['status'] = 'armed'
					end
				else
					update['status'] = codeMap[code]
				end
			else
				return	-- not a configured partition
			end
			
		elseif event.type == 'zone' then
		
			local zonenum = tonumber(parameters)
			
			if conf.zones[zonenum] then
				if conf.zones[zonenum].name then
					
					local codeMap = {
														[601] = 'alarm',
														[602] = 'noalarm',
														[603] = 'tamper',
														[604] = 'restore',
														[605] = 'fault',
														[606] = 'restore',
														[609] = 'open',
														[610] = 'closed',
														[631] = 'smoke',
														[632] = 'clear'
													}
													
					update =  {
											['type'] = 'zone',
											['name'] = conf.zones[zonenum].name,
											['value'] = tostring(zonenum),
											['status'] = codeMap[code]
										}
				else
					log.error (string.format('Zone name for zone %s not configured',zonenum))
					return
				end
			else
				return	--not a configured zone
			end
		else
			return	--- unprocessed event
		end
		
	else
		log.error ('Unknown event code encountered')
		return
	end
	
	return update
	
end
	

-- Login to Envisalink; once successful, send Refresh request
local function handle_login(code, parameters, event, message)

	if parameters == '3' then
		log.debug ('Received login password request; sending password')
		send_command('005', conf.envisalink.pass, true, true)
	elseif parameters == '1' then
		log.info('Successfully logged in to Envisalink; synching devices...')
		loggedin = true
		send_command('001', '', true, true)
		
	elseif parameters == '0' then
		log.error ('Envisalink login failed - incorrect password')
		return
	end
end		

	
local function format_msg(event, parameters)

	if event.type then
	
		if event.type == 'partition' then
		
			local partition_num = tonumber(parameters:sub(1,1))
			local partition_name
			if partition_num <= #conf.partitions then
				partition_name = conf.partitions[partition_num]
			else
				partition_name = tostring(partition_num)
			end
			
			if  partition_name then
				local usercode
				local paramlen = tostring(parameters):len()
				
				if paramlen == 5 then
					usercode = tonumber(parameters:sub(2,5))
					if not usercode then
						usercode = 0
					end
					
					local alarmusername = conf.usernames[usercode]
					
					if not alarmusername then
						alarmusername = usercode
					end
			
					return string.format(event.name, partition_name, tostring(alarmusername))
				
				elseif paramlen == 2 then
				
					local armmode = evl.ArmModes[tonumber(parameters:sub(2,2))]
					return string.format(event.name, partition_name, armmode)
				
				elseif paramlen == 1 then
					return string.format(event.name, partition_name)
				else
					return string.format(event.name, partition_name, tonumber(parameters:sub(2)))
				end
			end
		
		elseif event.type == 'zone' then
			local zonenum = tonumber(parameters)
			if conf.zones[zonenum] then
				if conf.zones[zonenum].name then
					return string.format(event.name, conf.zones[zonenum].name)
				end
			end
		end
	end		
		
	return string.format(event.name, tostring(parameters))	

end	

local function prettyprint(eventtab)

	local buildstr

	if eventtab.type then
	
		if eventtab.type == 'partition' then

			if eventtab.name then
				if eventtab.status then
					buildstr = '   {type: partition, name: ' .. eventtab.name .. ', value: ' .. eventtab.value .. ', status: ' .. eventtab.status
				else
					buildstr = '   {type: partition, name: ' .. eventtab.name .. ', value: ' .. eventtab.value
				end
			else
				buildstr = '   {type: partition, value: ' .. eventtab.value .. ', status: ' .. eventtab.status
			end
			
			if (eventtab.status == 'led') or (eventtab.status == 'ledflash') then
				buildstr = buildstr .. '\n\tparameters: {backlight: ' .. eventtab.parameters.backlight .. ', fire: ' .. eventtab.parameters.fire .. ', program: ' .. eventtab.parameters.program .. ', trouble: ' .. eventtab.parameters.trouble .. ', bypass: ' .. eventtab.parameters.bypass .. ', memory: ' .. eventtab.parameters.memory .. ', armed: ' .. eventtab.parameters.armed .. ', ready: ' .. eventtab.parameters.ready .. '}}'
			else
				buildstr = buildstr .. '}'
			end
		
		elseif eventtab.type == 'zone' then
		
			buildstr = '   {type: zone, name: ' .. eventtab.name .. ', value: ' .. eventtab.value .. ', status: ' .. eventtab.status .. '}'
		
		elseif eventtab.type == 'bypass' then
		
			buildstr = '   {type: bypass, status: ' .. eventtab.status .. ','
			buildstr = buildstr .. '\n\tparameters:  {'
			
			local n = 1
			for x, y in pairs(eventtab.parameters) do
				for zone, state in pairs(eventtab.parameters) do
					if tonumber(zone) == n then
						buildstr = buildstr .. zone .. ': ' .. state .. ', '
						break
					end
				end
				n = n + 1
			end
			buildstr = buildstr:sub(1, buildstr:len()-2) .. '}}'
		
		else
			for key, value in pairs(eventtab) do
				if type(value) ~= 'table' then
					buildstr = buildstr .. key .. ': ' .. value .. '\n'
				else
					buildstr = buildstr .. key .. ':\n'
					for key2, value2 in pairs(value) do
						buildstr = buildstr .. '\t' .. key2 .. ': ' .. value2
					end
				end
			end
		end
	end
	
	return buildstr

end


local function handle_line(input)

	if input then
	
		local code = tonumber(input:sub(1,3))
		local parameters = input:sub(4,-3)
		local event = evl.ResponseTypes[code]
		local message = format_msg(event, parameters)
		
		log.info ('RX < ' .. tostring(code) .. ' - ' .. parameters .. ' - ' .. message)

		local errcode
		if code == 502 then				-- System error
			errcode = tonumber(input:sub(4,6))
			print (' => ' .. message .. ' = ' .. evl.ErrorCodes[errcode])
		end
		
		local modparms = parameters
		local handler = evl.ResponseTypes[code]['handler']
		
		if handler then
			if handler == 'login' then
				handle_login(code, parameters, event, message)
				return
			else
				if handler == 'zone' then
					modparms = parameters:sub(2)
				elseif handler == 'partition' then
					modparms = parameters:sub(1,1)
				end
			end
		end
		
		local eventtable = build_event_table(code, modparms, event, message)
		
		if eventtable then
			--[[
			log.debug ('==================================================')
			for key, value in pairs(eventtable) do
				if type(value) ~= 'table' then
					log.debug (key, value)
				else
					log.debug (key .. ':')
					for key2, value2 in pairs(value) do
						log.debug ('\t' .. key2, value2)
					end
				end
			end
			log.debug ('==================================================')
			--]]
			log.info (prettyprint(eventtable))
			
			devhandler.process_message(eventtable)
			
		end		
	end
end


local function reconnect()

	timers.reconnect = evlDriver:call_with_delay(15, doreconnect, 'Re-connect timer')

end

------------------------------------------------------------------------
--							Channel Handler
------------------------------------------------------------------------

msghandler = function(_, sock)

	recvbuf, recverr = sock:receive('*l')
	
	if recverr ~= nil then
		log.debug ('Receive status =', recverr)
	end
	
	if (recverr ~= 'timeout') and recvbuf then
		log.debug ('RAW DATA RECEIVED: ' .. recvbuf)
		
		handle_line(recvbuf)
	
	elseif (recverr ~= 'timeout') and (recverr ~= nil) then
		log.error ('Socket Receive Error occured: ', recverr)
		
		if recverr == 'closed' then
			log.warn ('Envisalink has disconnected')
			disconnect()
			reconnect()
		
		end
	end	
end


synch = function()

	send_command('001', '')

end


local function is_loggedin()

	return loggedin

end

local function is_connected()

	return connected

end

local function inithandler(dev_handler)

	devhandler = dev_handler
	
end

return {
	inithandler = inithandler,
	connect = connect,
	disconnect = disconnect,
	reconnect = reconnect,
	msghandler = msghandler,
	devicesetup = devicesetup,
	synch = synch,
	send_command = send_command,
	is_connected = is_connected,
	is_loggedin = is_loggedin,
}

