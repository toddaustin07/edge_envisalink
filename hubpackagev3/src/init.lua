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
  
  Samsung SmartThings Edge Driver for Envisalink/DSC - main module for startup/initialization, and handling of SmartThings
  mobile app-initiated commands

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"

local cosock = require "cosock"                   -- cosock used only for sleep timer in this module
local socket = require "cosock.socket"
local log = require "log"

-- Driver-specific libraries
local evlClient = require "envisalink"
local devhandler = require "device_handler"
evlClient.inithandler(devhandler)

-- Global variables
evlDriver = {}
timers = { ['reconnect'] = nil, ['waitlogin'] = nil, ['poll'] = nil, ['pollreset'] = nil }
ZTYPE = 'zonetype'
MAXPARTITIONS = 8
MAXZONES = 64

-- Gobal Configuration table (populated via Panel device Settings)

conf = {  ['usernames']   = { [40] = 'master' },
          ['envisalink']  = {
                              ['ip'] = '192.168.1.nnn',
                              ['port'] = 4025,
                              ['pass'] = 'user'
                            },
          ['alarmcode']   = '1111',
          ['partitions']  = { 'DSC Primary Panel', },
          ['zones']       = {
                              {
                                ['name'] = 'Zone 1',
                                ['type'] = 'fubar',
                                ['partition'] = 1
                              },
                            }
        }

-- For code 849 - Verbose Trouble indicator
verboseTroubleMap = { 'time', 'sensorbatt', 'tamper', 'fault', 'comms', 'telephone', 'AC', 'service' }
verboseTroubleText =  {
                        ['service'] = 'Service Required',
                        ['AC'] = 'AC Power Lost',
                        ['telephone'] = 'Telephone Line Fault',
                        ['comms'] =  'Failure to Communicate',
                        ['fault'] =  'Sensor/Zone Fault',
                        ['tamper'] =  'Sensor/Zone Tamper',
                        ['sensorbatt'] =  'Sensor/Zone Battery',
                        ['time'] =  'Loss of Time',
                      }

-- Custom Capabilities (global)

cap_partitionstatus = capabilities["partyvoice23922.partitionstatus3a"]
cap_dscdashswitch = capabilities["partyvoice23922.dscdashswitch3"]
cap_ledstatus = capabilities["partyvoice23922.ledstatus2"]
cap_dscstayswitch = capabilities["partyvoice23922.dscstayswitch3"]
cap_dscawayswitch = capabilities["partyvoice23922.dscawayswitch3"]
cap_partitioncommand = capabilities["partyvoice23922.partitioncommand3"]
cap_dscselectswitch = capabilities["partyvoice23922.dscselectswitch3"]
cap_contactstatus = capabilities["partyvoice23922.contactstatus"]
cap_motionstatus = capabilities["partyvoice23922.motionstatus"]
cap_smokestatus = capabilities["partyvoice23922.smokestatus"]
cap_costatus = capabilities["partyvoice23922.costatus"]
cap_waterstatus = capabilities["partyvoice23922.waterstatus"]
cap_zonebypass = capabilities["partyvoice23922.zonebypass3a"]

cap_username = capabilities["partyvoice23922.dscuser"]
troubletype_capname = "partyvoice23922.dsctroubletype3a"
cap_trouble = capabilities[troubletype_capname]

-- Module variables
local initialized = false
local devices_initialized = 0
local total_devices = 0
local DASHCONFIG = 'dashconfig'
local valid_addr = false
local lastinfochange = socket.gettime()


-- Initialize connection to Envisalink - this is run on the device thread as a queued event
local function connect_to_envisalink(device)

  local client = evlClient.connect()

  if not client then
  
    log.warn ('Retrying to connect to Envisalink')
  
    local retries = 2
  
    repeat
      socket.sleep(5)
      client = evlClient.connect()
      retries = retries - 1
    until client or (retries == 0)
  end
    
  if client then  
    log.info ('Found and connected to Envisalink device')
    
    -- make sure we got logged in
    
    local retries = 2
    repeat 
      log.debug ('Waiting for login...')
      socket.sleep(3)
      retries = retries - 1
    until evlClient.is_loggedin() or (retries == 0)
    
    if evlClient.is_loggedin() then
      devhandler.onoffline('online')
      return true
      
    else
      evlClient.disconnect()
      device:emit_event(cap_partitionstatus.partStatus('* Login failed *'))
      log.error ('Failed to log into EnvisaLink')
    end
    
  else
    log.error ('Failed to connect to Envisalink')
    
  end

  -- if we get here, we couldn't connect, so queue up reconnect routine
  device.thread:queue_event(evlClient.reconnect)

end


-- Check IP:Port address for proper format & values
local function validate_address(lanAddress)

  local valid = true
  
  local ip = lanAddress:match('^(%d.+):')
  local port = tonumber(lanAddress:match(':(%d+)$'))
  
  if ip then
    local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
    if #chunks == 4 then
      for i, v in pairs(chunks) do
        if tonumber(v) > 255 then 
          valid = false
          break
        end
      end
    else
      valid = false
    end
  else
    valid = false
  end
  
  
  if port then
    if type(port) == 'number' then
      if (port < 1) or (port > 65535) then 
        valid = false
      end
    else
      valid = false
    end
  else
    valid = false
  end
  
  if valid then
    return ip, port
  else
    return nil
  end
      
end


local function update_usermap(device)

  if device.preferences.usermap then
    local map = device.preferences.usermap:gsub("%s+", "")
    for element in string.gmatch(map, '([^,]+)') do
      local code, name = element:match('^(%d+)=(%w+)$')
      local codenum = tonumber(code)
      if codenum and name then
        conf.usernames[codenum] = name
      else
        log.warn('Invalid username map')
        break
      end
    end
  end

end


-- Setup config preferences for Envisalink connection & DSC alarm code
local function initconfig(device)

  local ip
  local port
  local addr_is_valid = false
      
  ip, port = validate_address(device.preferences.lanAddress)
  if ip ~= nil then
    conf.envisalink.ip = ip
    conf.envisalink.port = port
    addr_is_valid = true
  else
    log.warn ('Invalid Envisalink LAN address')
  end
  
  
  conf.envisalink.pass = device.preferences.envPass
  
  if device.preferences.envPass:match('%W') == nil then
    if device.preferences.envPass:len() < 4 then
      log.warn ('Invalid Envisalink password (too short)')
    end
  else
    log.warn ('Invalid Envisalink password (not alphanumeric)')
  end
  
    
  conf.alarmcode = device.preferences.alarmCode
  local num_alarmcode = tonumber(device.preferences.alarmCode)
  local alarmcodelen = string.len(device.preferences.alarmCode)
  
  if num_alarmcode ~= nil then
    if (alarmcodelen < 4) or (alarmcodelen > 6) then
      log.warn('Invalid DSC alarmcode (not 4-6 digits')
    else
      log.debug (string.format('Alarm Code <%s> validated', conf.alarmcode)) 
    end
  else
    log.warn('Invalid DSC alarmcode (not a number)')
  end
  
  -- Parse usernames
  
  update_usermap(device)
  
  log.info (string.format('Using config prefs: %s:%d, password: %s, alarmcode: %s', conf.envisalink.ip, conf.envisalink.port, conf.envisalink.pass, conf.alarmcode))
  return(addr_is_valid)

end


local function disptable(table, tab)

  for key, value in pairs(table) do
    log.debug (tab .. key, value)
    if type(value) == 'table' then
      disptable(value, '  ' .. tab)
    end
  end
end

local function cmd_armstay(device)

  -- send arm stay command for partition
  device:emit_event(cap_partitionstatus.partStatus('Arming stay'))
  device:emit_event(cap_dscdashswitch.dashSwitch('On'))
  evlClient.send_command('031', device.device_network_id:match('DSC:P(%d+)'))

end

local function cmd_armaway(device)

  -- send arm away command for partition
  device:emit_event(cap_partitionstatus.partStatus('Arming away'))
  device:emit_event(cap_dscdashswitch.dashSwitch('On'))
  evlClient.send_command('030', device.device_network_id:match('DSC:P(%d+)'))

end

local function cmd_disarm(device)

  -- send disarm command for partition
  device:emit_event(cap_partitionstatus.partStatus('Disarming'))
	evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)

end

-----------------------------------------------------------------------
--										COMMAND HANDLERS
-----------------------------------------------------------------------

local function handle_dashswitch(_, device, command)
  
  log.debug("Dash switch command received = " .. command.command, command.args.value)
  
  local dashcfg = device:get_field(DASHCONFIG)
  
  if command.command == 'switchOn' then
    device:emit_event(cap_dscdashswitch.dashSwitch('On'))
    if dashcfg == 'away' then
      device:emit_event(cap_dscawayswitch.awaySwitch('On'))
      cmd_armaway(device)
    elseif dashcfg == 'stay' then
      device:emit_event(cap_dscstayswitch.staySwitch('On'))
      cmd_armstay(device)
    end
  
  else
    device:emit_event(cap_dscdashswitch.dashSwitch('Off'))
    if dashcfg == 'away' then
      device:emit_event(cap_dscawayswitch.awaySwitch('Off'))
      cmd_disarm(device)
    elseif dashcfg == 'stay' then
      device:emit_event(cap_dscstayswitch.staySwitch('Off'))
      cmd_disarm(device)
    end
    
  end
  
end


local function handle_stayswitch(_, device, command)
  
  log.debug("Stay switch command received = " .. command.command, command.args.state)
  
  local arm = false
  
  if ((command.command == 'setSwitch') and (command.args.state == 'On')) or command.command == 'switchOn' then
    arm = true
  end
  
  if arm then
    device:emit_event(cap_dscstayswitch.staySwitch('On'))
		cmd_armstay(device)
	else
    device:emit_event(cap_dscstayswitch.staySwitch('Off'))
    cmd_disarm(device)
	end
  
end


local function handle_awayswitch(_, device, command)
  
  log.debug("Away switch command received = " .. command.command, command.args.state)
  
  local arm = false
  
  if ((command.command == 'setSwitch') and (command.args.state == 'On')) or command.command == 'switchOn' then
    arm = true
  end
  
  if arm then
    device:emit_event(cap_dscawayswitch.awaySwitch('On'))
		cmd_armaway(device)
	else
    device:emit_event(cap_dscawayswitch.awaySwitch('Off'))
    cmd_disarm(device)
	end
  
end


local function handle_partcmd(driver, device, command)
  
  log.debug("Partition command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_partitioncommand.partitionCommand(command.args.value))
  
	local partcmd = command.args.value
  local partition = device.device_network_id:match('DSC:P(%d+)')
  local partcmdtable = 	{
													['instantstay'] = {'071', partition .. '*9'},
													['instantaway'] = {'032', partition},
													['togglenight'] = {'071', partition .. '**#'},
													['togglechime'] = {'071', partition .. '*4#'},
													['reset'] = {'071', partition .. '*72#'},
													['refresh'] = {'001', ''},
													['panicfire'] = {'060', '1'},
                          ['panicamb'] = {'060', '2'},
                          ['panicpolice'] = {'060', '3'},
                          ['pgm1'] = {'071', partition .. '*71#'},
                          ['pgm2'] = {'071', partition .. '*72#'},
                          ['pgm3'] = {'071', partition .. '*73#'},
                          ['pgm4'] = {'071', partition .. '*74#'},
												}
  
  if partcmd == 'armaway' then
    device:emit_event(cap_dscawayswitch.awaySwitch('On'))
    cmd_armaway(device)
  elseif partcmd == 'armstay' then
    device:emit_event(cap_dscstayswitch.staySwitch('On'))
    cmd_armstay(device)
  elseif partcmd == 'disarm' then
    cmd_disarm(device)
  else
    evlClient.send_command(partcmdtable[partcmd][1], partcmdtable[partcmd][2])
    
    if partcmd == device.preferences.sirenpgm then
      device:emit_event(capabilities.alarm.alarm('siren'))
      device.thread:call_with_delay(device.preferences.sirenduration, function() device:emit_event(capabilities.alarm.alarm('off')); end, 'clear siren')
    end
  end
  
  device.thread:call_with_delay(3, function() device:emit_event(cap_partitioncommand.partitionCommand(' ', {visibility = {displayed = false}})); end, 'clear partcmd')
  
end


local function handle_select(_, device, command)
  
  log.debug("Select switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscselectswitch.selection(command.args.value))
  
  device:set_field(DASHCONFIG, command.args.value, { ['persist'] = true })
  
end


local function handle_zonebypass(_, device, command)

  log.debug(string.format('Bypass command for %s: cmd: [%s], value: [%s]', device.label, command.command, command.args.value))
  
  local action = 'off'
  
  if (command.command == 'setZoneBypass') and (command.args.value == 'On') then
    action = 'on'
  elseif command.command == 'switchOn' then
    action = 'on'
  end
  
  --[[
  if action == 'on' then
    device:emit_event(cap_zonebypass.zoneBypass('On', { visibility = { displayed = false } })
  else
    device:emit_event(cap_zonebypass.zoneBypass('Off', { visibility = { displayed = false } })
  end
  --]]
  device:emit_event(cap_zonebypass.mylabel('Toggling Bypass...'))
  
  local zonenumber = device.device_network_id:match('DSC:Z(%d+)')
  local partition = device.device_network_id:match('DSC:Z%d+_(%d+)')
  
  if string.len(zonenumber) == 1 then
    zonenumber = '0' .. zonenumber
  end
  
  log.debug (string.format('Toggling Bypass for Partition %s, Zone %s', partition, zonenumber))
  evlClient.send_command('071', partition .. '*1' .. zonenumber .. '#')
  
end

local function handle_siren(_, device, command)

  log.debug('Alarm command: ', command.command)
  
  if (command.command == 'siren') or (command.command == 'both') then
  
    local pgm = device.preferences.sirenpgm:match('pgm(%d)')
    
    if pgm ~= '0' then
      device:emit_event(capabilities.alarm.alarm(command.command))
      local partition = device.device_network_id:match('DSC:P(%d+)')
      evlClient.send_command('071', partition .. '*7' .. pgm .. '#')
      device.thread:call_with_delay(device.preferences.sirenduration, function() device:emit_event(capabilities.alarm.alarm('off')); end, 'clear siren')
      return
    end
  end
  
  device:emit_event(capabilities.alarm.alarm('off'))

end


local function handle_STHM(_, device, command)

  log.debug('Received STHM command: ', command.command)
  
  if device.preferences.sthmsynch == 'yessynch' then
  
    if command.command == 'armAway' then
      device:emit_event(capabilities.securitySystem.securitySystemStatus('armedAway'))
      cmd_armaway(device)
    
    elseif command.command == 'armStay' then
      device:emit_event(capabilities.securitySystem.securitySystemStatus('armedStay'))
      cmd_armstay(device)
    
    elseif command.command == 'disarm' then
      device:emit_event(capabilities.securitySystem.securitySystemStatus('disarmed'))
      cmd_disarm(device)
    
    else
      log.error ('Unexpected STHM command:', command.command)
    end
    
  end

end

--======================================================================
--                REQUIRED EDGE DRIVER HANDLERS
--======================================================================

-- Lifecycle handler to initialize existing devices AND newly created devices
local function device_init(driver, device)

  log.debug(device.id .. ": " .. device.device_network_id .. " > INITIALIZING")
  
  devices_initialized = devices_initialized + 1


  -- Handle case where new zone created while already connected to Envisalink

  if evlClient.is_loggedin() then
    device:online()
  else
    device:offline()
  end
  
  -- Initialize device config
  
  if device.device_network_id:find('DSC:Z', 1, 'plaintext') then
  
    local zonenum = tonumber(device.device_network_id:match('DSC:Z(%d+)'))
    local partnum = tonumber(device.device_network_id:match('DSC:Z%d+_(%d+)'))
    
    conf.zones[zonenum] = {
                           ['name'] = string.format('Partition %d Zone %d', partnum, zonenum),
                           ['type'] = device.model:match('^DSC%-(%w+)'),
                           ['partition'] = partnum,
                          }
    
    log.debug (string.format('Zone configured: %s (type=%s)', conf.zones[zonenum].name, conf.zones[zonenum].type))
    
    
  elseif device.device_network_id:find('DSC:P', 1, 'plaintext') then

    local partnum = tonumber(device.device_network_id:match('DSC:P(%d+)'))
    
    if partnum > 1 then
      conf.partitions[partnum] = device.label
    end
  
    local dashconv = {
                        ['away'] = 'Arm Away',
                        ['stay'] = 'Arm Stay',
                        ['none'] = 'No action'
                      }
  
    local dashconfig = device:get_field(DASHCONFIG)
    log.debug ('saved dashconfig=', dashconfig)
    if not dashconv[dashconfig] then; dashconfig = nil; end
    if not dashconfig then
      dashconfig = 'away'
      device:set_field(DASHCONFIG, 'away', { ['persist'] = true })
    end

    device:emit_event(cap_dscselectswitch.selection(dashconv[dashconfig]))
    device:emit_event(cap_partitioncommand.partitionCommand(' '))

    log.debug (string.format('Partition %d Settings preferences...', partnum))
    disptable(device.preferences, '  ')

    -- If this is the Primary panel
    if partnum == 1 then
    
      if not conf.partitions[1] then
        conf.partitions[1] = 'DSC Primary Panel'
      end  
        
      valid_addr = initconfig(device)                   -- initialize config from preferences
      
      timers.poll = driver:call_on_schedule(device.preferences.checkfreq * 60, evlClient.periodic_check)
      
      initialized = true 
    
    end    
  end
        
  -- Once all devices have been initialized, connect to Envisalink
  if devices_initialized == total_devices then

    if valid_addr == true then
    
      if not evlClient.is_loggedin() then
        if not evlClient.is_connected() then
          device.thread:queue_event(connect_to_envisalink, device)
        end
      end
    else
      log.debug ('Cannot connect yet; Envisalink address needs configuring')
    end
  end

end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.id .. ": " .. device.device_network_id .. " > ADDED")
  
  if device.device_network_id:find('DSC:Z', 1, 'plaintext') then
  
    device:emit_event(cap_zonebypass.zoneBypass('Off'))
    device:emit_event(cap_zonebypass.mylabel('-'))
    
    log.debug('New device model:', device.model)
    local ztype = device.model:match('DSC%-(%w+)')
    log.debug('New device type:', ztype)
    
    if ztype == 'contact' then
      device:emit_event(capabilities.contactSensor.contact('closed'))
      device:emit_event(cap_contactstatus.contactStatus('-'))
    
    elseif ztype == 'motion' then
      device:emit_event(capabilities.motionSensor.motion('inactive'))
      device:emit_event(cap_motionstatus.motionStatus('-'))
    
    elseif ztype == 'smoke' then
      device:emit_event(capabilities.smokeDetector.smoke('clear'))
      device:emit_event(cap_smokestatus.smokeStatus('-'))
    
    elseif ztype == 'co' then
      device:emit_event(capabilities.carbonMonoxideDetector.carbonMonoxide('clear'))
      device:emit_event(cap_costatus.coStatus('-'))
    
    elseif ztype == 'water' then
      device:emit_event(capabilities.waterSensor.water('dry'))
      device:emit_event(cap_waterstatus.waterStatus('-'))
    
    end
  
  elseif device.device_network_id:find('DSC:P', 1, 'plaintext') then
  
    device:emit_event(cap_dscdashswitch.dashSwitch('Off'))
    device:emit_event(cap_partitionstatus.partStatus('-'))
    device:emit_event(cap_ledstatus.ledStatus('-'))
    device:emit_event(cap_username.username('-'))
    device:emit_event(cap_trouble.troubleType('-'))
    
    device:emit_event(cap_dscstayswitch.staySwitch('Off'))
    device:emit_event(cap_dscawayswitch.awaySwitch('Off'))
    device:emit_event(cap_partitioncommand.partitionCommand(' '))
    
    device:emit_event(capabilities.alarm.alarm('off'))
    device:emit_event(capabilities.securitySystem.securitySystemStatus('disarmed'))
    device:set_field(DASHCONFIG, 'away', { ['persist'] = true })
    
  end
  
  total_devices = total_devices + 1
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  -- Nothing to do here!

end


-- Called when device was deleted via mobile app
local function device_removed(_, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. " > REMOVED")
  
  local partnum = tonumber(device.device_network_id:match('^DSC:P(%d+)'))
  
  if partnum then
    conf.partitions[partnum] = nil
  end
  
  local zonenum = tonumber(device.device_network_id:match('^DSC:Z(%d+)'))
  
  if zonenum then
    conf.zones[zonenum].name = nil
    conf.zones[zonenum].type = nil
    conf.zones[zonenum].partition = nil
  end

  -- shutdown if no more devices 
  
  local device_list = evlDriver:get_devices()
  
  if #device_list == 0 then
    log.info ('All devices removed; shutting down Envisalink connection')
    initialized = false
    evlClient.disconnect()  
  end
end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end

-- **************************
-- Handle changes in Settings
-- **************************
local function handler_infochanged (driver, device, event, args)
  
  log.debug ('Info changed handler invoked')
  
  -- If this is the primary partition panel...

  if device.device_network_id == 'DSC:P1' then
  
    -- Did preferences change?
    if args.old_st_store.preferences then
    
      local changed = false
      local connection_changed = false
      
      -- Examine preference settings to see if it changed
     
      -- LAN ADDRESS
     
      if args.old_st_store.preferences.lanAddress ~= device.preferences.lanAddress then
        changed = true
        connection_changed = true
        log.debug (string.format('LAN address changed from %s to %s',args.old_st_store.preferences.lanAddress, device.preferences.lanAddress))
      end

      -- ENVISALINK PASSWORD, ALARM CODE

      if (args.old_st_store.preferences.envPass ~= device.preferences.envPass) or
          (args.old_st_store.preferences.alarmCode ~= device.preferences.alarmCode) then
        changed = true
      end
      
      -- USER NAME MAP
      if args.old_st_store.preferences.usermap ~= device.preferences.usermap then
        update_usermap(device)
      end
      
      -- Poll frequency
      if args.old_st_store.preferences.checkfreq ~= device.preferences.checkfreq then
        if timers.poll then
          driver:cancel_timer(timers.poll)
        end
        timers.poll = driver:call_on_schedule(device.preferences.checkfreq * 60, evlClient.periodic_check)
      end 

      -- ADDITIONAL PARTITIONS
      
      if (args.old_st_store.preferences.addlparts ~= device.preferences.addlparts) then
        log.debug ('Additional partition preference change from/to: ', args.old_st_store.preferences.addlparts, device.preferences.addlparts)
        if device.preferences.addlparts < MAXPARTITIONS then
          local addlparts_qty = device.preferences.addlparts - args.old_st_store.preferences.addlparts
          if addlparts_qty > 0 then
            for partnum = #conf.partitions, device.preferences.addlparts do
              devhandler.createpanel(partnum+1)
            end
          end
        end
      end
      
      
      if changed then  
        valid_addr = initconfig(device)
      
      -- Determine if need to (re) connect
      
        if connection_changed and valid_addr then
        
          log.info ('Renewing connection to Envisalink')

          if timers.reconnect then
            driver:cancel_timer(timers.reconnect)
          end
          if timers.waitlogin then
            driver:cancel_timer(timers.waitlogin)
          end
          timers.reconnect = nil
          socket.sleep(.1)
          timers.waitlogin = nil
            
          if evlClient.is_connected() then
            evlClient.disconnect()
          end
          
          device.thread:queue_event(connect_to_envisalink, device)
        end
      end
    end
  end
  
  -- process zone type updates
  if device.device_network_id:find('DSC:P', 1, 'plaintext') then
      
    local partition = tonumber(device.device_network_id:match('DSC:P(%d+)'))
    
    for zone = 1, MAXZONES do
      local zkey = 'zone' .. tostring(zone)
      if args.old_st_store.preferences[zkey] ~= device.preferences[zkey] then
        devhandler.proczonesetting(device, zone, args.old_st_store.preferences[zkey], device.preferences[zkey], partition)
      end
    end
    
  end
    
end

-- If the hub's IP address changes, this handler is called
local function lan_info_changed_handler(driver, hub_ipv4)
  if driver.listen_ip == nil or hub_ipv4 ~= driver.listen_ip then
    log.info("Hub IP address has changed, restarting Envisalink connection")
    
    if evlClient.is_connected() then
      evlClient.disconnect()
    end
    
    device.thread:queue_event(connect_to_envisalink, device)
  end
end


-- Create only Primary Panel Device
local function discovery_handler(driver, _, should_continue)
  
  if not initialized then
  
    log.info("Creating Primary DSC Panel Device")
    
    devhandler.createpanel(1)
    
    log.debug("Exiting Discovery")
    
  else
    log.info ('Primary DSC Panel already created')
  end
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
evlDriver = Driver("evlDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  capability_handlers = {
    [cap_dscdashswitch.ID] = {
      [cap_dscdashswitch.commands.switchOn.NAME] = handle_dashswitch,
      [cap_dscdashswitch.commands.switchOff.NAME] = handle_dashswitch,
    },
    [cap_dscstayswitch.ID] = {
      [cap_dscstayswitch.commands.setSwitch.NAME] = handle_stayswitch,
      [cap_dscstayswitch.commands.switchOn.NAME] = handle_stayswitch,
			[cap_dscstayswitch.commands.switchOff.NAME] = handle_stayswitch,
    },
    [cap_dscawayswitch.ID] = {
      [cap_dscawayswitch.commands.setSwitch.NAME] = handle_awayswitch,
      [cap_dscstayswitch.commands.switchOn.NAME] = handle_awayswitch,
			[cap_dscstayswitch.commands.switchOff.NAME] = handle_awayswitch,
    },
    [cap_partitioncommand.ID] = {
      [cap_partitioncommand.commands.setPartitionCommand.NAME] = handle_partcmd,
    },
    [cap_dscselectswitch.ID] = {
      [cap_dscselectswitch.commands.setSelection.NAME] = handle_select,
    },
    [cap_zonebypass.ID] = {
      [cap_zonebypass.commands.setZoneBypass.NAME] = handle_zonebypass,
      [cap_zonebypass.commands.switchOn.NAME] = handle_zonebypass,
      [cap_zonebypass.commands.switchOff.NAME] = handle_zonebypass,
    },
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = handle_siren,
      [capabilities.alarm.commands.off.NAME] = handle_siren,
      [capabilities.alarm.commands.siren.NAME] = handle_siren,
      [capabilities.alarm.commands.strobe.NAME] = handle_siren,
    },
    [capabilities.securitySystem.ID] = {
      [capabilities.securitySystem.commands.armAway.NAME] = handle_STHM,
      [capabilities.securitySystem.commands.armStay.NAME] = handle_STHM,
      [capabilities.securitySystem.commands.disarm.NAME] = handle_STHM,
    }
  }
})

log.info ('v3.0 Driver Started: supporting EyezOn EnvisaLink 2DS/3/4')

local device_list = evlDriver:get_devices()
total_devices = #device_list
log.debug ('Number of devices assigned to this driver: ', total_devices)


evlDriver:run()
