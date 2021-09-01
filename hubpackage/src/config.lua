-- Pretty names for the user ids that arm/disarm alarm.
local usernames = { [40] = 'Austin', [80] = 'MyUser2' }

-- Envisalink device
-- Host: Replace this with the hostname or IP (preferred) of the EVL device
-- Port: The default EVL port is 4025
-- Password: The default EVL password is "user"
local envisalink = 	{
											['host'] = '192.168.1.104',
											['port'] = 4025,
											['pass'] = 'user'
										}

-- Alarm code: If defined you can disarm the alarm without having to 
-- enter a code. 
local alarmcode = 1755

-- Partition Definitions: Only defined partitions will be generated 
-- Add more [partitionX] sections if you have more than one partition.
local partitions = 	{	
											{
												['name'] = 'Home',
												['stay'] = 'DSC Stay Panel',
												['away'] = 'DSC Away Panel'
											},
										}

-- Zone Definitions: Only the defined zones will be generated.
-- Delete any unused zones to have them removed.
-- Add more sections if you need to define more zones.
-- Devices: co (carbonMonoxide), contact, motion, smoke, water
local zones = 	{
									{
										['name'] = 'DSC Zone 01 Door to Garage',
										['type'] = 'contact',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 02 Master BR',
										['type'] = 'contact',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 03 Inlaw Suite',
										['type'] = 'contact',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 04 Downstairs & Upfr BR',
										['type'] = 'contact',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 05 Gameroom & Back BR',
										['type'] = 'contact',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 06 Motion Detector',
										['type'] = 'motion',
										['partition'] = 1
									},
									{
										['name'] = 'DSC Zone 07 Front Door',
										['type'] = 'contact',
										['partition'] = 1
									}
								}

return	{
					usernames = usernames,
					envisalink = envisalink,
					alarmcode = alarmcode,
					partitions = partitions,
					zones = zones,
				}
