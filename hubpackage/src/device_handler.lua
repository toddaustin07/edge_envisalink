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

--]]


local capabilities = require "st.capabilities"
local log = require "log"
local cosock = require "cosock"                   -- cosock used only for sleep timer in this module
local socket = require "cosock.socket" 


-- Device capability profiles
local profiles = {
  ["primarypanel"] = "DSC.primarypanel.v2",
  ["secondarypanel"] = "DSC.secondarypanel.v1",
  ["contact"] = "DSC.contactzone.v1",
  ["motion"] = "DSC.motionzone.v1",
  ["smoke"] = "DSC.smokezone.v1",	
  ["co"] = "DSC.cozone.v1",
  ["water"] = "DSC.waterzone.v1",
}

-- Device metadata
local MFG_NAME = 'Digital Security Controls'
local PANEL_MODEL = 'DSC panel'
local VEND_LABEL = 'PowerSeries'

-- Module variables
local ALARMMEMORY = {}
local STpartitionstatus = {[1]='', [2]='', [3]='', [4]='', [5]='', [6]='', [7]='', [8]=''}


local function emitSensorState(msg, sensorstate)

	local device_list = evlDriver:get_devices()
	for _, device in ipairs(device_list) do
		if device.device_network_id:match('^DSC:Z(%d+)') == msg.value then
			local zonetype = device.model:match('^DSC%-(%w+)')
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

	local device_list = evlDriver:get_devices()
	for _, device in ipairs(device_list) do
		if device.device_network_id:match('^DSC:Z(%d+)') == msg.value then
			local zonetype = device.model:match('^DSC%-(%w+)')
			if zonetype == 'contact' then
				device:emit_event(cap_contactstatus.contactStatus(zonestatus))
	
			elseif zonetype == 'motion' then
				device:emit_event(cap_motionstatus.motionStatus(zonestatus))
				
			elseif zonetype == 'smoke' then
				device:emit_event(cap_smokestatus.smokeStatus(zonestatus))
			
			elseif zonetype == 'co' then
				device:emit_event(cap_costatus.coStatus(zonestatus))
				
			elseif zonetype == 'water' then
				device:emit_event(cap_waterstatus.waterStatus(zonestatus))
				
			end
		end
	end
end


local function proc_zone_msg(msg)

	local SENSORSTATE = {
													['contact'] = { ['open'] = 'open', ['closed'] = 'closed' },
													['motion'] = { ['open'] = 'active', ['closed'] = 'inactive' },
													['smoke'] = { ['smoke'] = 'detected',	['clear'] = 'clear' },
													['co'] = { ['smoke'] = 'detected', ['clear'] = 'clear' },
													['water'] = { ['open'] = 'wet', ['closed'] = 'dry' },
												}
	
	local ZONESTATUS =	{
												['contact'] = { ['open'] = 'Open',	['closed'] = 'Closed' },
												['motion'] = { ['open'] = 'Motion', ['closed'] = 'No motion' },
												['smoke'] = { ['smoke'] = 'Smoke detected', ['clear'] = 'Clear' },
												['co'] = { ['smoke'] = 'CO detected', ['clear'] = 'Clear' },
												['water'] = { ['open'] = 'Wet', ['closed'] = 'Dry' },
											}
	
	local zonetype = conf.zones[tonumber(msg.value)].type
	
	log.debug (string.format('Processing zone update; zonetype= >>%s<<', zonetype))
	
	if zonetype ~= nil then
	
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
	else
		log.warn (string.format('Zone %d device not configured', tonumber(msg.value)))
	end
end    


local function proc_bypass_msg(msg)

	local bypass = msg.parameters
	local BYPASSSTATE = {
												['on'] = 'Bypass is on',
												['off'] = 'Bypass is off',
											}
											
	local device_list = evlDriver:get_devices()

  for _, device in ipairs(device_list) do
		local zonenum = device.device_network_id:match('^DSC:Z(%d+)')
		if zonenum then
			local bypassvalue = bypass[zonenum]
			if bypassvalue then
				device:emit_event(cap_zonebypass.zoneBypass(BYPASSSTATE[bypassvalue]))
			end
		end
  end

end


local function proc_partition_msg(msg)

	local device_list = evlDriver:get_devices()

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
														['entrydelay'] = 'Entry delay',
														['stay'] = 'Armed-stay',
														['away'] = 'Armed-away',
														['armed'] = 'Armed',
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
					
					local priorstatus = STpartitionstatus[tonumber(msg.value)]
					STpartitionstatus[tonumber(msg.value)] = display_status
					log.debug(string.format('Processing Partition #%s %s (%s): priorstatus=%s', msg.value, msg.status, display_status, priorstatus))
					
					if (display_status == 'Ready') then
						if priorstatus ~= 'Ready' then
							--device:emit_event(cap_dscdashswitch.switch('off'))
							--device:emit_event(cap_dscstayswitch.switch('off'))
							--device:emit_event(cap_dscawayswitch.switch('off'))
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
						if (msg.status ~= 'armed') then
							device:emit_event(cap_partitionstatus.partStatus(display_status))
						end
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
 
 
local function createpanel(partnum)

	-- Create panel device
	
	local id = 'DSC:P' .. tostring(partnum)
	local devprofile
	local devlabel
	
	if partnum == 1 then
		devprofile = profiles['primarypanel']
		conf.partitions[partnum] = 'DSC Primary Panel'
		devlabel = conf.partitions[partnum]
	else
		devprofile = profiles['secondarypanel']
		devlabel = string.format('DSC P%d Panel', partnum)
	end
		
	local create_device_msg = {
															type = "LAN",
															device_network_id = id,
															label = devlabel,
															profile = devprofile,
															manufacturer = MFG_NAME,
															model = PANEL_MODEL,
															vendor_provided_label = VEND_LABEL,
														}
												
	log.info(string.format("Creating Partition #%d Panel (%s): '%s'", partnum, id, devlabel))

	assert (evlDriver:try_create_device(create_device_msg), "failed to create panel device")

end


-- Process Settings changes for zone preferences
local function proczonesetting(device, zonenum, oldztype, newztype, partnum)

	log.debug (string.format('Zone %d setting change from %s to %s', zonenum, oldztype, newztype))

	local alreadyexists = false

	local device_list = evlDriver:get_devices()

	for _, device in ipairs(device_list) do
	
		if tonumber(device.device_network_id:match('^DSC:Z(%d+)')) == zonenum then
			alreadyexists = true
			break
		end
	end

	if alreadyexists then
		if newztype == 'unused' then
			conf.zones[zonenum].name = nil
			conf.zones[zonenum].type = nil
			conf.zones[zonenum].partition = nil
			log.warn (string.format('Zone %d disabled', zonenum))
		else
			log.error ('Cannot change device type; user delete required')
		end
		-- can't change type of exisiting zone to anything but 'unused'
	
	-- It's a new zone device	
	elseif newztype ~= 'unused' then
		
		-- Create zone device
		
		local id = 'DSC:Z' .. tostring(zonenum) .. '_' .. tostring(partnum)
		local name = string.format ('Partition %d Zone %d', partnum, zonenum)
		local devprofile = profiles[newztype]
		local create_device_msg = {
																type = "LAN",
																device_network_id = id,
																label = name,
																profile = devprofile,
																manufacturer = MFG_NAME,
																model = 'DSC-' .. newztype,
																vendor_provided_label = VEND_LABEL,
															}
												
		log.info(string.format("Creating %s device (%s); type=%s", name, id, newztype))

		assert (evlDriver:try_create_device(create_device_msg), "failed to create zone device")
	end
end 


local function onoffline(status)

	local device_list = evlDriver:get_devices()

  for _, device in ipairs(device_list) do
		if status == 'online' then
			device:online()
		elseif status == 'offline' then
			device:offline()
		end
	end

end

 
return {
	createpanel = createpanel,
	proczonesetting = proczonesetting,
	process_message = process_message,
	onoffline = onoffline,
}
