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
  
  Samsung SmartThings Edge Driver for Envisalink - module to handle SmartThings device setup and state updates
  based on Envisalink messages

  ** This code is a port based on the alarmserver Python package originally developed by donnyk+envisalink@gmail.com,
  which also included subsequent modifications/enhancements by leaberry@gmail.com, jordan@xeron.cc, ralphtorchia1@gmail.com

--]]


local capabilities = require "st.capabilities"
local log = require "log"

local conf = require 'config'

--[[
-- Custom Capabilities
local cap_partitionstatus = capabilities["partyvoice23922.partitionStatus"]
local cap_dscdashswitch = capabilities["partyvoice23922.dscdashswitch"]
local cap_ledstatus = capabilities["partyvoice23922.ledStatus"]
local cap_dscstayswitch = capabilities["partyvoice23922.dscstayswitch"]
local cap_dscawayswitch = capabilities["partyvoice23922.dscawayswitch"]
local cap_partitioncommand = capabilities["partyvoice23922.partitioncommand"]
local cap_dscselectswitch = capabilities["partyvoice23922.dscselectswitch"]
local cap_contactstatus = capabilities["partyvoice23922.contactstatus"]
local cap_motionstatus = capabilities["partyvoice23922.motionstatus"]
local cap_zonebypass = capabilities["partyvoice23922.zonebypass"]
--]]

-- Device capability profiles
local profiles = {
  ["panel"] = "DSC.panel.v2",
  ["contact"] = "DSC.contactzone.v1",
  ["motion"] = "DSC.motionzone.v1",
  ["smoke"] = "DSC.contactzone.v1",		-- ** Needs work
  ["co"] = "DSC.contactzone.v1",			-- ** Needs work
}

local STdriver
local ALARMMEMORY = {}
local armedflag = false
local STpartitionstatus = ''


local function emitSensorState(msg, sensorstate)

	local device_list = STdriver:get_devices()
	for _, device in ipairs(device_list) do
		if device.device_network_id:match('^DSC:Z(%d+)') == msg.value then
			local zonetype = device.model:match('^DSC (%g+)')
			if zonetype == 'contact' then
				device:emit_event(capabilities.contactSensor.contact(sensorstate))
	
			elseif zonetype == 'motion' then
				device:emit_event(capabilities.motionSensor.motion(sensorstate))
				
			elseif zonetype == 'smoke' then
				device:emit_event(capabilities.smokeDetector.smoke(sensorstate))
			
			elseif zonetype == 'co' then
				device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide(sensorstate))
				
			elseif zonetype == 'water' then
				device:emit_event(capabilities.waterSensor.water(sensorstate))
				
			end
		end
	end
end


local function emitZoneStatus(msg, zonestatus)

	local device_list = STdriver:get_devices()
	for _, device in ipairs(device_list) do
		if device.device_network_id:match('^DSC:Z(%d+)') == msg.value then
			local zonetype = device.model:match('^DSC (%g+)')
			if zonetype == 'contact' then
				device:emit_event(cap_contactstatus.contactStatus(zonestatus))
	
			elseif zonetype == 'motion' then
				device:emit_event(cap_motionstatus.motionStatus(zonestatus))
				
			elseif zonetype == 'smoke' then				-- NEED TO ADD ZONE STATUS CAPABILITIES FOR THESE NEXT 3
				local x = 1
			
			elseif zonetype == 'co' then
				local x = 1
				
			elseif zonetype == 'water' then
				local x = 1
				
			end
		end
	end
end


local function proc_zone_msg(msg)

	local SENSORSTATE = {
													['contact'] = { ['open'] = 'open', ['closed'] = 'closed' },
													['motion'] = { ['open'] = 'active', ['closed'] = 'inactive' },
													['smoke'] = { ['smoke'] = 'detected',	['clear'] = 'clear' },
													['o2'] = { ['smoke'] = 'detected', ['clear'] = 'clear' },
													['water'] = { ['open'] = 'wet', ['closed'] = 'dry' },
												}
	
	local ZONESTATUS =	{
												['contact'] = { ['open'] = 'Open',	['closed'] = 'Closed' },
												['motion'] = { ['open'] = 'Motion', ['closed'] = 'No motion' },
												['smoke'] = { ['smoke'] = 'Smoke detected', ['clear'] = 'Clear' },
												['o2'] = { ['smoke'] = 'O2 detected', ['clear'] = 'Clear' },
												['water'] = { ['open'] = 'Wet', ['closed'] = 'Dry' },
											}
	
	local zonetype = conf.zones[tonumber(msg.value)].type
	
	if (msg.status == 'open') or (msg.status == 'closed') or 
		 (msg.status == 'smoke') or (msg.status == 'clear') then
		
		local sensstate = SENSORSTATE[zonetype][msg.status]
		if sensstate == nil then; sensstate = msg.status; end 
		
		emitSensorState(msg, sensstate)
	end	
	
	if msg.status == 'alarm' then
		ALARMMEMORY[tonumber(msg.value)] = true
		emitZoneStatus(msg, 'ALARM!')
	end
	
	if not ALARMMEMORY[tonumber(msg.value)] then
		local zonestat = ZONESTATUS[zonetype][msg.status]
		if zonestat == nil then; zonestat = msg.status; end

		emitZoneStatus(msg, zonestat)
	end
	
end    


local function proc_bypass_msg(msg)

	local bypass = msg.parameters
	local BYPASSSTATE = {
												['on'] = 'Bypass is on',
												['off'] = 'Bypass is off',
											}
											
	local device_list = STdriver:get_devices()

  for _, device in ipairs(device_list) do
		local zonenum = device.device_network_id:match('^DSC:Z(%d+)')
		if zonenum then
			local bypassvalue = bypass[zonenum]
			
			device:emit_event(cap_zonebypass.zoneBypass(BYPASSSTATE[bypassvalue]))
		end
  end

end


local function proc_partition_msg(msg)

	local device_list = STdriver:get_devices()

  for _, device in ipairs(device_list) do
  
		if device.device_network_id:match('^DSC:P(%d+)') == msg.value then
		
			if msg.status then
			
				if msg.status == 'led' then

					local ledstat = msg.parameters
					local indicators = ''

					if ledstat.fire == 'on' then
						indicators = indicators .. 'Fire*'
					end
					if ledstat.trouble == 'on' then
						indicators = indicators .. 'Trouble*'
					end
					if ledstat.memory == 'on' then
						indicators = indicators .. 'Memory*'
					end
					if ledstat.bypass == 'on' then
						indicators = indicators .. 'Bypass*'
					end
					
					if indicators:len() > 0 then
						indicators = indicators:sub(1,-2)
					else
						indicators = '-'
					end
					
					device:emit_event(cap_ledstatus.ledStatus(indicators))
					
			
				elseif msg.status ~= 'ledflash' then
				
					local DISPLAY = {
														['ready'] = 'Ready',
														['restore'] = 'Ready',
														['notready'] = 'Not ready',
														['forceready'] = 'Ready',
														['exitdelay'] = 'Exit delay',
														['stay'] = 'Armed-stay',
														['away'] = 'Armed-away',
														['disarm'] = 'Disarmed',
														['alarm'] = 'ALARM!!',
														['chime'] = 'Chime on',
														['nochime'] = 'Chime off',
														['trouble'] = 'Trouble',
													}
					
					local display_status = DISPLAY[msg.status]
					if display_status == nil then
						display_status = msg.status
					end
					
					local priorstatus = STpartitionstatus
					STpartitionstatus = display_status
					
					if (display_status == 'Ready') then
						if priorstatus ~= 'Ready' then
							device:emit_event(cap_partitionstatus.partStatus(display_status))
						end
					
					elseif msg.status == 'stay' then
						device:emit_event(cap_dscdashswitch.switch('on'))
						device:emit_event(cap_dscstayswitch.switch('on'))
						device:emit_event(cap_partitionstatus.partStatus(display_status))
						armedflag = true
					
					elseif msg.status == 'away' then
						device:emit_event(cap_dscdashswitch.switch('on'))
						device:emit_event(cap_dscawayswitch.switch('on'))
						device:emit_event(cap_partitionstatus.partStatus(display_status))
						armedflag = true
					
					elseif msg.status == 'disarm' then
						device:emit_event(cap_dscdashswitch.switch('off'))
						device:emit_event(cap_dscstayswitch.switch('off'))
						device:emit_event(cap_dscawayswitch.switch('off'))
						armedflag = false
					
					else
						device:emit_event(cap_partitionstatus.partStatus(display_status))
					end
					
					-- If arming, need to reset zones with alarm memory
					
					if msg.status == 'exitdelay' then			
						
						for zonenum, zone in ipairs(conf.zones) do
							if (zone.partition == tonumber(msg.value)) then
								if ALARMMEMORY[zonenum] == true then
									local _msg = { ['value'] = tostring(zonenum) }
									if (zone.type == 'contact') or (zone.type == 'motion') or (zone.type == 'water') then
										emitZoneStatus(_msg, 'Closed')
									elseif (zone.type == 'motion') then
										emitZoneStatus(_msg, 'No Motion')
									elseif (zone.type == 'smoke') or (zone.type == 'co') then
										emitZoneStatus(_msg, 'Clear')
									elseif (zone.type == 'water') then
										emitZoneStatus(_msg, 'Dry')
									end
								end
								
								ALARMMEMORY[zonenum] = false
							end
						end
					end
					
				end
			end
			break
				
		end
	end

end
    
    
local function process_message(msg)
 
	if msg.type == 'partition' then
	
		proc_partition_msg(msg)
		
	elseif msg.type == 'zone' then
		
		proc_zone_msg(msg)
		
	elseif msg.type == 'bypass' then
	
		proc_bypass_msg(msg)
		
	else
	
		log.error ('Unrecognized message - ignoring')
		
	end
 
end
 

local function devicesetup(driver)

	local MFG_NAME = 'Digital Security Controls'
	local PANEL_MODEL = 'DSC panel'
	local VEND_LABEL = 'PowerSeries'

	-- Create zone devices
	
	for zonenum, zone in ipairs(conf.zones) do
	
		local id = 'DSC:Z' .. tostring(zonenum)
		local devprofile = profiles[zone.type]
		local create_device_msg = {
																type = "LAN",
																device_network_id = id,
																label = zone.name,
																profile = devprofile,
																manufacturer = MFG_NAME,
																model = 'DSC ' .. zone.type,
																vendor_provided_label = VEND_LABEL,
															}
                        
		log.info(string.format("Creating Zone #%d device (%s): '%s'; type=%s", zonenum, id, zone.name, zone.type))

		assert (driver:try_create_device(create_device_msg), "failed to create zone device")
	
	end
	
	
	-- Create panel device
	
	for partnum, partition in ipairs(conf.partitions) do
	
		local id = 'DSC:P' .. tostring(partnum)
		local devprofile = profiles['panel']
		local create_device_msg = {
																type = "LAN",
																device_network_id = id,
																label = partition.name,
																profile = devprofile,
																manufacturer = MFG_NAME,
																model = PANEL_MODEL,
																vendor_provided_label = VEND_LABEL,
															}
												
		log.info(string.format("Creating Partition #%d Panel (%s): '%s'", partnum, id, partition.name))

		assert (driver:try_create_device(create_device_msg), "failed to create panel device")
	end
	
end 


local function initpanel(device)

	device:emit_event(cap_dscdashswitch.switch('off'))
	device:emit_event(cap_dscstayswitch.switch('off'))
	device:emit_event(cap_dscawayswitch.switch('off'))
	
	local dashconfig = device:get_field(DASHCONFIG)
	if dashconfig then
		device:emit_event(cap_dscselectswitch.switch(command.args.value))
	else
		device:emit_event(cap_dscselectswitch.switch('type: Arm STAY'))
	end
	

end

local function initialize(driver)

	STdriver = driver
	
end




 
return {
	initialize = initialize,
	devicesetup = devicesetup,
	process_message = process_message,
	initpanel = initpanel,
}
