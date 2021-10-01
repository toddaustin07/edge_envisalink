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
  
  Samsung SmartThings Edge Driver for Envisalink - main module for startup/initialization, and handling of SmartThings
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
timers = { ['reconnect'] = nil, ['waitlogin'] = nil }
armedflag = false
ZTYPE = 'zonetype'

-- Gobal Configuration table (populated via primary Panel device Settings)

conf = {  ['usernames']   = { [40] = 'Edge', [80] = 'MyUser2' },
          ['envisalink']  = {
                              ['ip'] = '192.168.1.nnn',
                              ['port'] = 4025,
                              ['pass'] = 'user'
                            },
          ['alarmcode']   = 1111,
          ['partitions']  = { 'DSC Panel', },
          ['zones']       = {
                              {
                                ['name'] = 'Zone 1',
                                ['type'] = 'fubar',
                                ['partition'] = 1
                              },
                            }
        }


-- Custom Capabilities (global)
---[[
local capdefs = require 'capabilitydefs'

cap_partitionstatus = capabilities.build_cap_from_json_string(capdefs.partitionstatus)
cap_dscdashswitch = capabilities.build_cap_from_json_string(capdefs.dscdashswitch)
cap_ledstatus = capabilities.build_cap_from_json_string(capdefs.ledstatus)
cap_dscstayswitch = capabilities.build_cap_from_json_string(capdefs.dscstayswitch)
cap_dscawayswitch = capabilities.build_cap_from_json_string(capdefs.dscawayswitch)
cap_partitioncommand = capabilities.build_cap_from_json_string(capdefs.partitioncommand)
cap_dscselectswitch = capabilities.build_cap_from_json_string(capdefs.dscselectswitch)
cap_contactstatus = capabilities.build_cap_from_json_string(capdefs.contactstatus)
cap_motionstatus = capabilities.build_cap_from_json_string(capdefs.motionstatus)
cap_smokestatus = capabilities.build_cap_from_json_string(capdefs.smokestatus)
cap_costatus = capabilities.build_cap_from_json_string(capdefs.costatus)
cap_waterstatus = capabilities.build_cap_from_json_string(capdefs.waterstatus)
cap_zonebypass = capabilities.build_cap_from_json_string(capdefs.zonebypass)


capabilities["partyvoice23922.partitionStatus"] = cap_partitionstatus
capabilities["partyvoice23922.dscdashswitch"] = cap_dscdashswitch
capabilities["partyvoice23922.ledStatus"] = cap_ledstatus
capabilities["partyvoice23922.dscstayswitch"] = cap_dscstayswitch
capabilities["partyvoice23922.dscawayswitch"] = cap_dscawayswitch
capabilities["partyvoice23922.partitioncommand"] = cap_partitioncommand
capabilities["partyvoice23922.dscselectswitch"] = cap_dscselectswitch
capabilities["partyvoice23922.contactstatus"] = cap_contactstatus
capabilities["partyvoice23922.motionstatus"] = cap_motionstatus
capabilities["partyvoice23922.smokestatus"] = cap_smokestatus
capabilities["partyvoice23922.costatus"] = cap_costatus
capabilities["partyvoice23922.waterstatus"] = cap_waterstatus
capabilities["partyvoice23922.zonebypass"] = cap_zonebypass
--]]

--[[
cap_partitionstatus = capabilities["partyvoice23922.partitionStatus"]
cap_dscdashswitch = capabilities["partyvoice23922.dscdashswitch"]
cap_ledstatus = capabilities["partyvoice23922.ledStatus"]
cap_dscstayswitch = capabilities["partyvoice23922.dscstayswitch"]
cap_dscawayswitch = capabilities["partyvoice23922.dscawayswitch"]
cap_partitioncommand = capabilities["partyvoice23922.partitioncommand"]
cap_dscselectswitch = capabilities["partyvoice23922.dscselectswitch"]
cap_contactstatus = capabilities["partyvoice23922.contactstatus"]
cap_motionstatus = capabilities["partyvoice23922.motionstatus"]
cap_smokestatus = capabilities["partyvoice23922.smokestatus"]
cap_costatus = capabilities["partyvoice23922.costatus"]
cap_waterstatus = capabilities["partyvoice23922.waterstatus"]
cap_zonebypass = capabilities["partyvoice23922.zonebypass"]
--]]

-- Module variables
local initialized = false
local devices_initialized = 0
local total_devices = 0
local DASHCONFIG = 'dashconfig'
local valid_addr = false


-- Initialize connection to Envisalink
local function connect_to_envisalink()

  local client = evlClient.connect()

  if not client then
  
    log.warn ('Retrying to connect to Envisalink')
  
    local retries = 2
  
    repeat
      socket.sleep(5)
      client = evlClient.connect()
      retries = retries - 1
    until retries == 0
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
      log.error ('Failed to log into EnvisaLink')
    end
    
  else
    log.error ('Failed to connect to Envisalink')
  end

  return false

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
  
    
  conf.alarmcode = tonumber(device.preferences.alarmCode)
  
  if conf.alarmcode ~= nil then
    if string.len(device.preferences.alarmCode) ~= 4 then
      log.warn('Invalid DSC alarmcode (not 4 digits')
    end
  else
    log.warn('Invalid DSC alarmcode (not a number)')
  end
  
  log.info (string.format('Using config prefs: %s:%d, password: %s, alarmcode: %d', conf.envisalink.ip, conf.envisalink.port, conf.envisalink.pass, conf.alarmcode))
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

-----------------------------------------------------------------------
--										COMMAND HANDLERS
-----------------------------------------------------------------------

local function handle_dashswitch(_, device, command)
  
  log.debug("Dash switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscdashswitch.switch(command.args.value))
  
  if command.args.value == 'on' then
    local dashcfg = device:get_field(DASHCONFIG)
    
    if dashcfg == 'type: Arm AWAY' then
      -- send arm away command for partition
      device:emit_event(cap_partitionstatus.partStatus('Arming away'))
      evlClient.send_command('030', device.device_network_id:match('DSC:P(%d+)'))
      
    else
      -- send arm stay command for partition
      device:emit_event(cap_partitionstatus.partStatus('Arming stay'))
      evlClient.send_command('031', device.device_network_id:match('DSC:P(%d+)'))
    end
  
  else
    device:emit_event(cap_partitionstatus.partStatus('Disarming'))
		evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)
  end
  
end


local function handle_stayswitch(_, device, command)
  
  log.debug("Stay switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscstayswitch.switch(command.args.value))
  if command.args.value == 'on' then
		device:emit_event(cap_partitionstatus.partStatus('Arming stay'))
		evlClient.send_command('031', device.device_network_id:match('DSC:P(%d+)'))
	else
    if armedflag then
      device:emit_event(cap_partitionstatus.partStatus('Disarming'))
      evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)
    end
	end
  
end


local function handle_awayswitch(_, device, command)
  
  log.debug("Away switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscawayswitch.switch(command.args.value))
  if command.args.value == 'on' then
		device:emit_event(cap_partitionstatus.partStatus('Arming away'))
		evlClient.send_command('030', device.device_network_id:match('DSC:P(%d+)'))
	else
    if armedflag then
      device:emit_event(cap_partitionstatus.partStatus('Disarming'))
      evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)
    end
	end
  
end


local function handle_partcmd(_, device, command)
  
  log.debug("Partition command received = " .. command.command, command.args.value)
  
	local partcmd = command.args.value
  local partition = device.device_network_id:match('DSC:P(%d+)')
  local partcmdtable = 	{
													['instantarm'] = {'071', partition .. '*9' .. conf.alarmcode .. '#'},
													['toggleinstant'] = {'032', partition},
													['togglenight'] = {'071', partition .. '**#'},
													['togglechime'] = {'071', partition .. '*4#'},
													['reset'] = {'071', partition .. '*72#'},
													['refresh'] = {'001', ''},
													['panicfire'] = {'060', '1'},
                          ['panicamb'] = {'060', '2'},
                          ['panicpolice'] = {'060', '3'},
												}
  
  evlClient.send_command(partcmdtable[partcmd][1], partcmdtable[partcmd][2])
  
  device:emit_event(cap_partitioncommand.partitionCommand(' '))
  
end


local function handle_select(_, device, command)
  
  log.debug("Select switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscselectswitch.switch(command.args.value))
  
  device:set_field(DASHCONFIG, command.args.value, { ['persist'] = true })
  
end


local function handle_zonebypass(_, device, command)

  log.debug(string.format('Bypass command for %s: cmd: [%s], value: [%s]', device.device_network_id, command.command, command.args.value))
  device:emit_event(cap_zonebypass.zoneBypass(' '))
  
  local zonenumber = device.device_network_id:match('DSC:Z(%d+)')
  
  local partition = tostring(conf.zones[tonumber(zonenumber)].partition)
  
  if string.len(zonenumber) == 1 then
    zonenumber = '0' .. zonenumber
  end
  
  log.debug (string.format('Toggling Bypass for Partition %s, Zone %s', partition, zonenumber))
  evlClient.send_command('071', partition .. '*1' .. zonenumber .. '#')
  
end

--======================================================================
--                REQUIRED EDGE DRIVER HANDLERS
--======================================================================

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)

  log.debug(device.id .. ": " .. device.device_network_id .. " > INITIALIZING")
  
  device:offline()
  devices_initialized = devices_initialized + 1
  
  -- Initialize device config
  
  if device.device_network_id:find('DSC:Z', 1, 'plaintext') then
  
    local zonenum = tonumber(device.device_network_id:match('DSC:Z(%d+)'))
    
    conf.zones[zonenum] = {
                           ['name'] = string.format ('Partition %d Zone %d', 1, zonenum),
                           ['type'] = device.model:match('^DSC%-(%w+)'),
                           ['partition'] = 1,
                          }
    
    log.debug (string.format('Zone configured: %s (type=%s)', conf.zones[zonenum].name, conf.zones[zonenum].type))
    
  end
    
  if device.device_network_id:find('DSC:P', 1, 'plaintext') then
  
    local dashconfig = device:get_field(DASHCONFIG)
    if dashconfig then
      device:emit_event(cap_dscselectswitch.switch(dashconfig))
    else
      device:emit_event(cap_dscselectswitch.switch('type: Arm STAY'))
    end

    -- If this is the Primary panel
    if device.device_network_id:match('DSC:P(%d+)') == '1' then
      
      log.debug ('Settings preferences...')
      disptable(device.preferences, '  ')
      
      valid_addr = initconfig(device)                   -- initialize config from preferences
      
      initialized = true 
    
    end    
  end
        
  if devices_initialized == total_devices then
  
    if valid_addr == true then
    
      if not evlClient.is_loggedin() then              -- don't think it ever would be at this point
        if not evlClient.is_connected() then
          if not connect_to_envisalink() then
            evlClient.reconnect()
          end
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
  
    device:emit_event(cap_zonebypass.zoneBypass('-'))
  
  elseif device.device_network_id:find('DSC:P', 1, 'plaintext') then
  
    device:emit_event(cap_partitionstatus.partStatus('-'))
    device:emit_event(cap_dscdashswitch.switch('off'))
    device:emit_event(cap_dscstayswitch.switch('off'))
    device:emit_event(cap_dscawayswitch.switch('off'))
    
  end
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  -- Nothing to do here!

end


-- Called when device was deleted via mobile app
local function device_removed(_, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. " > REMOVED")
  
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
    
      --[[
      log.debug ('OLD preferences:')
      for key, value in pairs(args.old_st_store.preferences) do
        log.debug ('\t' .. key, value)
      end
      log.debug ('NEW preferences:')
      for key, value in pairs(device.preferences) do
        log.debug ('\t' .. key, value)
      end
      --]]
      
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
          
          if not connect_to_envisalink() then
            evlClient.reconnect()
          end
        end
      end
      
      -- process zone type updates
      
      devhandler.proczonesetting(device, 1, args.old_st_store.preferences.zone1, device.preferences.zone1, 1)
      devhandler.proczonesetting(device, 2, args.old_st_store.preferences.zone2, device.preferences.zone2, 1)
      devhandler.proczonesetting(device, 3, args.old_st_store.preferences.zone3, device.preferences.zone3, 1)
      devhandler.proczonesetting(device, 4, args.old_st_store.preferences.zone4, device.preferences.zone4, 1)
      devhandler.proczonesetting(device, 5, args.old_st_store.preferences.zone5, device.preferences.zone5, 1)
      devhandler.proczonesetting(device, 6, args.old_st_store.preferences.zone6, device.preferences.zone6, 1)
      devhandler.proczonesetting(device, 7, args.old_st_store.preferences.zone7, device.preferences.zone7, 1)
      devhandler.proczonesetting(device, 8, args.old_st_store.preferences.zone8, device.preferences.zone8, 1)
      devhandler.proczonesetting(device, 9, args.old_st_store.preferences.zone9, device.preferences.zone9, 1)
      devhandler.proczonesetting(device, 10, args.old_st_store.preferences.zone10, device.preferences.zone10, 1)
      devhandler.proczonesetting(device, 11, args.old_st_store.preferences.zone11, device.preferences.zone11, 1)
      devhandler.proczonesetting(device, 12, args.old_st_store.preferences.zone11, device.preferences.zone12, 1)
      
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
    
    if not connect_to_envisalink() then
      evlClient.reconnect()
    end
  end
end


-- Create only Primary Panel Device
local function discovery_handler(driver, _, should_continue)
  
  if not initialized then
  
    log.info("Creating Primary Panel Device")
    
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
      [cap_dscdashswitch.commands.setSwitch.NAME] = handle_dashswitch,
    },
    [cap_dscstayswitch.ID] = {
      [cap_dscstayswitch.commands.setSwitch.NAME] = handle_stayswitch,
    },
    [cap_dscawayswitch.ID] = {
      [cap_dscawayswitch.commands.setSwitch.NAME] = handle_awayswitch,
    },
    [cap_partitioncommand.ID] = {
      [cap_partitioncommand.commands.setPartitionCommand.NAME] = handle_partcmd,
    },
    [cap_dscselectswitch.ID] = {
      [cap_dscselectswitch.commands.setSwitch.NAME] = handle_select,
    },
    [cap_zonebypass.ID] = {
      [cap_zonebypass.commands.setZoneBypass.NAME] = handle_zonebypass,
    },
  }
})

log.info ('Driver Started: supporting EyezOn EnvisaLink 2DS/3/4')

local device_list = evlDriver:get_devices()
if #device_list > 1 then
  log.debug ('Number of devices assigned to this driver: ', #device_list)
  total_devices = #device_list
else
  total_devices = 1
end

evlDriver:run()
