-- Pretty names for the user ids that arm/disarm alarm (used only for log messages)
local usernames = { [40] = 'Austin', [80] = 'MyUser2' }

-- Envisalink device
-- ip: Set this to the IP address of the Envisalink device
-- port: The default Envisalink port is 4025
-- pass: The default Envisalink password is "user"
local envisalink = 	{
											['ip'] = '192.168.1.104',
											['port'] = 4025,
											['pass'] = 'user'
										}

-- Alarm code: If defined you can disarm the alarm without having to 
-- enter a code. 
local alarmcode = 1755

-- Partition Definitions: Only defined partitions will be generated 
-- Add more panel names in quotes separated by commas if you have more than one partition.
local partitions = 	{	'DSC Panel', }

-- Zone Definitions: Only the defined zones will be generated.
-- MUST be in proper sequential order of defined DSC zones (1..n)
-- Add more sections if you need to define more zones.
-- Valid Types: contact, motion, smoke, co (carbonMonoxide), water
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
