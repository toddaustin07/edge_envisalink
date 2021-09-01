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
local capabilities = require "st.capabilities"
local cosock = require "cosock"                   -- cosock used only for sleep timer in this module
local socket = require "cosock.socket"
local log = require "log"

-- Driver-specific libraries
local evlClient = require "envisalink"
local devhandler = require "device_handler"
local conf = require "config"

-- Global variables
local evlDriver = {}
local devices_created = 0
local devices_initialized = 0
local initialized = false
local DASHCONFIG = 'dashconfig'

-- Custom Capabilities (global)
cap_partitionstatus = capabilities["partyvoice23922.partitionStatus"]
cap_dscdashswitch = capabilities["partyvoice23922.dscdashswitch"]
cap_ledstatus = capabilities["partyvoice23922.ledStatus"]
cap_dscstayswitch = capabilities["partyvoice23922.dscstayswitch"]
cap_dscawayswitch = capabilities["partyvoice23922.dscawayswitch"]
cap_partitioncommand = capabilities["partyvoice23922.partitioncommand"]
cap_dscselectswitch = capabilities["partyvoice23922.dscselectswitch"]
cap_contactstatus = capabilities["partyvoice23922.contactstatus"]
cap_motionstatus = capabilities["partyvoice23922.motionstatus"]
cap_zonebypass = capabilities["partyvoice23922.zonebypass"]


local function connect_to_envisalink()

  local clientsock = evlClient.connect(evlDriver)

  if not clientsock then
  
    log.warn ('Retrying to connect to Envisalink')
  
    local retries = 2
  
    repeat
      socket.sleep(5)
      clientsock = evlClient.connect(evlDriver)
      retries = retries - 1
    until retries == 0
  end
    
  if clientsock then  
    log.info ('Found and connected to Envisalink device')
    evlDriver:register_channel_handler(clientsock, evlClient.msghandler, 'LAN client handler')
    
    -- make sure we got logged in
    
    local retries = 5
    repeat 
      log.debug ('Waiting for login...')
      socket.sleep(1)
      retries = retries - 1
    until evlClient.is_loggedin() or (retries == 0)
    
    if evlClient.is_loggedin() then
      log.info('Successfully logged in to Envisalink')
      return true
      
    else
      evlDriver:unregister_channel_handler(clientsock)
      evlClient.disconnect(clientsock)
      log.error ('Failed to log into EnvisaLink')
    end
    
  else
    log.error ('Failed to connect to Envisalink')
  end

  return false

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
		device:emit_event(cap_partitionstatus.partStatus('Disarming'))
		evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)
	end
  
end

local function handle_awayswitch(_, device, command)
  
  log.debug("Away switch command received = " .. command.command, command.args.value)
  
  device:emit_event(cap_dscawayswitch.switch(command.args.value))
  if command.args.value == 'on' then
		device:emit_event(cap_partitionstatus.partStatus('Arming away'))
		evlClient.send_command('030', device.device_network_id:match('DSC:P(%d+)'))
	else
		device:emit_event(cap_partitionstatus.partStatus('Disarming'))
		evlClient.send_command('040', device.device_network_id:match('DSC:P(%d+)') .. conf.alarmcode)
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
													['refresh'] = {'001'},
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

------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices (unreliably invoked after device_added handler)
local function device_init(driver, device)
  
  log.debug(device.id .. ": " .. device.device_network_id .. "> INITIALIZING")
  
  device:online()

  devices_initialized = devices_initialized + 1
  
  -- Initialize panel switches
  if device.device_network_id:find('DSC:P', 1, 'plaintext') then
    devhandler.initpanel(device)
  end
  
  if devices_initialized == (#conf.zones + #conf.partitions) then

    devhandler.initialize(driver)

    initialized = true
    local connect = false
    
    if not evlClient.is_loggedin() then
      connected = connect_to_envisalink(driver)
    end
  
    if not connected then
      evlClient.reconnect()
    end
  end

end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.id .. ": " .. device.device_network_id .. "> successfully added")
  
  devices_created = devices_created + 1
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  -- Nothing to do here!

end


-- Called when device was deleted via mobile app
local function device_removed(_, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")
  
end

-- If the hub's IP address changes, this handler is called
local function lan_info_changed_handler(driver, hub_ipv4)
  if driver.listen_ip == nil or hub_ipv4 ~= driver.listen_ip then
    log.info("Hub IP address has changed, restarting eventing server and resubscribing")
    
  end
end


-- Perform SSDP discovery to find, and connect-to, Envisalink device on the LAN
local function discovery_handler(driver, _, should_continue)
  
  if not initialized then
  
    log.debug("Starting discovery")
    
    if connect_to_envisalink() then
      devhandler.devicesetup(driver)
    end
    
    log.info("Driver is exiting discovery")
    
  else
    log.debug ('Driver already initialized')
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
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  lan_info_changed_handler = lan_info_changed_handler,
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
  }
})

log.info ('Driver Started: supporting EyezOn EnvisaLink 2DS/3/4')


evlDriver:run()
