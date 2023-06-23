--[[
  Copyright 2021, 2022, 2023 Todd Austin

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

local evlClient = require "envisalink"

-- Device capability profiles
local profiles = {
  ["primarypanel"] = "DSC.primarypanel.v3d",
  ["secondarypanel"] = "DSC.secondarypanel.v3d",
  ["contact"] = "DSC.contactzone.v3",
  ["motion"] = "DSC.motionzone.v3",
  ["smoke"] = "DSC.smokezone.v3",	
  ["co"] = "DSC.cozone.v3",
  ["water"] = "DSC.waterzone.v3",
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
													['smoke'] = { ['open'] = 'detected', ['closed'] = 'clear' },
													['co'] = { ['open'] = 'detected', ['closed'] = 'clear' },
													['water'] = { ['open'] = 'wet', ['closed'] = 'dry' },
												}
	
	local ZONESTATUS =	{
												['contact'] = { ['open'] = 'Open',	['closed'] = 'Closed' },
												['motion'] = { ['open'] = 'Motion', ['closed'] = 'No motion' },
												['smoke'] = { ['open'] = 'Smoke detected', ['closed'] = 'Clear' },
												['co'] = { ['open'] = 'CO detected', ['closed'] = 'Clear' },
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
				device:emit_event(cap_zonebypass.mylabel(BYPASSSTATE[bypassvalue]))
				if bypassvalue == 'on' then
					device:emit_event(cap_zonebypass.zoneBypass('On', { visibility = { displayed = false } }))
				else
					device:emit_event(cap_zonebypass.zoneBypass('Off', { visibility = { displayed = false } }))
				end
			end
		end
  end

end


local function arm_reset(device)
	
	device:emit_event(cap_dscstayswitch.staySwitch('Off'))
	device:emit_event(capabilities.alarm.alarm('off'))
	device:emit_event(cap_dscawayswitch.awaySwitch('Off'))
	device:emit_event(cap_dscdashswitch.dashSwitch('Off'))
	
end


local function update_troublemsg(troubletext, options)

	local device_list = evlDriver:get_devices()
	for _, device in ipairs(device_list) do
  
		if device.device_network_id:find('DSC:P', 1) then
			device:emit_event(cap_trouble.troubleType(troubletext, options))
			if troubletext == ' ' then
				device:emit_event(cap_partitionstatus.partStatus('Trouble restore'))
				STpartitionstatus[tonumber(device.device_network_id:match('DSC:P(%d)'))] = 'Trouble restore'
			end
		end
	end

end


local function proc_troublestate(msg)

	local troubletext
	local options = nil
	
	local trouble_text = 	{
													['AC'] = 'AC Power Lost',
													['battery'] = 'Battery',
													['bell'] = 'Bell'
												}
	
	if msg.status:find('trouble_', 1) then
		troubletext = trouble_text[msg.status:match('trouble_(%w+)$')]
	elseif msg.status:find('restore_', 1) then
		troubletext = ' '
		options = { visibility = { displayed = false } }
	end

	update_troublemsg(troubletext, options)

end


local function proc_verbosetrouble(device, msg)

	log.debug ('Current trouble type: ', device.state_cache.main[troubletype_capname].troubleType.value)
	-- If Battery or Bell trouble type already set, then ignore verbose trouble (probably a 'Service Required')
	if (device.state_cache.main[troubletype_capname].troubleType.value == 'Battery') or
	   (device.state_cache.main[troubletype_capname].troubleType.value == 'Bell') then
	  return
	end

	local troubletext = ''
	local sep = ''
	local options = nil

	for vtrouble, state in pairs(msg.parameters) do
		
		if state == 'on' then
			troubletext = troubletext .. sep .. verboseTroubleText[vtrouble]
			sep = ', '
		end
	end
	
	if troubletext == '' then
		troubletext = ' '
		options = { visibility = { displayed = false } }
	end
	
	update_troublemsg(troubletext, options)
	
end


local function proc_partition_msg(msg)

	local device_list = evlDriver:get_devices()

    for _, device in ipairs(device_list) do
  
		if device.device_network_id:match('^DSC:P(%d+)') == msg.value then
		
			if msg.status then
			
				if msg.status == 'led' then

					local ledstat = msg.parameters
					local indicators = ''
					local options = nil

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
						options = { visibility = { displayed = false } }
					end
					
					-- these can change quickly, so to prevent rate limits, schedule in 1 second
					evlDriver:call_with_delay(1, function()
							device:emit_event(cap_ledstatus.ledStatus(indicators, options))
						end)
					
				elseif msg.status:find('trouble_', 1) or msg.status:find('restore_', 1) then
					
					proc_troublestate(msg)
					
				elseif msg.status == 'verbosetrouble' then
				
					proc_verbosetrouble(device, msg)
					
				elseif msg.status == 'restoreled' then
					update_troublemsg(' ', { visibility = { displayed = false } })
			
				elseif (msg.status ~= 'ledflash') and (msg.status ~= 'restoreled') and (msg.status ~= 'specialclose') then
				
					local DISPLAY = {
														['ready'] = 'Ready',
														['restore'] = 'Restore',
														['notready'] = 'Not ready',
														['cantarm'] = 'Not ready to arm',
														['notarmed'] = 'Not armed',
														['forceready'] = 'Ready',
														['exitdelay'] = 'Exit delay',
														['entrydelay'] = 'Entry delay',
														['stay'] = 'Armed-stay',
														['instantstay'] = 'Armed-stay (instant)',
														['away'] = 'Armed-away',
														['instantaway'] = 'Armed-away (instant)',
														['armed'] = 'Armed',
														['disarm'] = 'Disarmed',
														['alarm'] = 'ALARM!!',
														['chime'] = 'Chime on',
														['nochime'] = 'Chime off',
														['troubleled'] = 'Trouble',
														['restoreled'] = 'Restore LED',
														['specialclose'] = 'Special close',
													}
					
					local display_status = DISPLAY[msg.status]
					if display_status == nil then
						display_status = msg.status
					end
					
					local priorstatus = STpartitionstatus[tonumber(msg.value)]
					
					if display_status == 'Restore' then
						if priorstatus ~= 'Trouble' then
							display_status = priorstatus
						end
					end
					
					STpartitionstatus[tonumber(msg.value)] = display_status
					log.debug(string.format('Processing Partition #%s %s (%s): priorstatus=%s', msg.value, msg.status, display_status, priorstatus))
					
					if (display_status == 'Ready') then
						if priorstatus ~= 'Ready' then
							device:emit_event(cap_partitionstatus.partStatus(display_status))
						end
						
						if priorstatus == 'ALARM!!' then
							arm_reset(device)
						end
					
					elseif msg.status == 'stay' or msg.status == 'instantstay' then
						device:emit_event(cap_dscdashswitch.dashSwitch('On'))
						device:emit_event(cap_dscstayswitch.staySwitch('On'))
						device:emit_event(cap_partitionstatus.partStatus(display_status))
					
					elseif msg.status == 'away' or msg.status == 'instantaway' then
						device:emit_event(cap_dscdashswitch.dashSwitch('On'))
						device:emit_event(cap_dscawayswitch.awaySwitch('On'))
						device:emit_event(cap_partitionstatus.partStatus(display_status))
					
					elseif (msg.status == 'disarm') then
						arm_reset(device)
						device:emit_event(cap_partitionstatus.partStatus(display_status))
					
					else
						if (msg.status ~= 'armed') then
							device:emit_event(cap_partitionstatus.partStatus(display_status))
							if msg.status == 'cantarm' then
								arm_reset(device)
							elseif msg.status == 'alarm' then
								device:emit_event(capabilities.alarm.alarm('siren'))
							end
						end
					end
					
					-- Display username if available
					
					if (msg.status == 'userclose') or (msg.status == 'useropen') then
						device:emit_event(cap_username.username(msg.username))
					end
					
					if (msg.status == 'exitdelay') then
						device:emit_event(cap_username.username(' ',{visibility={displayed=false}}))
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

local function codereq(msg)

	log.info('Sending access code')
	evlClient.send_command('200', conf.alarmcode)

end
    
    
local function process_message(msg)
 
	if msg.type == 'partition' then
	
		proc_partition_msg(msg)
		
	elseif msg.type == 'zone' then
		
		proc_zone_msg(msg)
		
	elseif msg.type == 'bypass' then
	
		proc_bypass_msg(msg)
		
	elseif msg.type == 'codereq' then
	
		codereq(msg)
		
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
			if device.device_network_id:find('DSC:P', 1, 'plaintext') then
				device:emit_event(cap_partitionstatus.partStatus('Offline'))
			end
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
