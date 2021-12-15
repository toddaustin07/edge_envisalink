# SmartThings Edge Device Driver for DSC/Envisalink

**NOTE:  THIS DRIVER STILL IN TEST**

This Edge driver is targeted to users having a DSC security system with an Envisalink board connecting it to the local LAN.  Edge drivers run directly on a SmartThings hub.  The driver will connect with the Envisalink to create and update devices reflecting your DSC system partition panels and zones.

The typical (but not exclusive) audiance has an existing solution using the 'Alarmserver' package. Alarmserver is a Python-based program that runs on a LAN-connected computer (often a Raspberry Pi) and connects to an Envisalink module to pass messages back and forth to SmartThings.  However Alarmserver is based on the legacy DTH / SmartApp / graph callback implementation which will be sunset by SmartThings.  This driver provides a migration path for those Alarmserver users and offers a number of additional benefits as outlined below.

### Benefits
- Eliminates dependency on Groovy DTHs, which is being sunset
- No SmartApp is required
- Eliminates need for separate stay / away panel devices
- Eliminates need for separate computer to run Envisalink interfacing code
- Leverages 100% local execution of Edge platform (including related automations)
- Can be run in parallel with existing Alarmserver setup for low risk transition

### Pre-requisites
- SmartThings hub V2 or later
- Connected and running Envisalink interface; know its IP address and port #

### Optional
- SmartThings CLI with Edge authorizations (https://github.com/SmartThingsCommunity/smartthings-cli/tree/master/packages/cli#smartthings-devicespresentation-id)
For viewing logging output

### Migrating from Alarmserver
This package does not prereq the Alarmserver package.  However if the user already has that running, there is a setup option where you can run both solutions in parallel.  You must be running the latest Alarmserver package from Ralph Torchia (https://github.com/rtorchia/DSC-Envisalink/tree/master/alarmserver), to ensure a functioning proxy server.  Then when configuring the Edge driver per instructions below, you can point the Edge driver to the IP address and port of the Alarmserver proxy server, which will provide a passthrough to the Envisalink.  When you are happy with everything functioning with the new Edge driver configuration, you can change its IP configuration to point directly to the Envisalink device and shutdown Alarmserver.

### Caveats
- This package should be considered beta-level; SmartThings Edge is still in beta as of November 2021
- Limited testing has been done for smoke, carbon monoxide (co), and water zones

## Setup Instructions

### Install the Envisalink Edge Driver to your hub
Use this channel invite:  https://api.smartthings.com/invitation-web/accept?id=2345136d-b4ea-4e4d-8632-7496a1fb368c

Sign in to SmartThings, enroll your hub to this channel, list the available drivers, and select to install 'Envisalink 2'

#### Start logging (optional)
Use the CLI to find out the driver ID and start the logger in a window on your computer
```
smartthings edge:drivers:installed
smartthings edge:drivers:logcat <driverID> --hub-address=<hub IP addr>
```
Here you will see all messages to and from the Envisalink, as well as other driver logging output and SmartThings platform messages.  Running the logger is not required once everything is up and running to your satisfaction.

*Note: you won't see anything being logged until you peform the next step.*
  
### Initialize and Configure the Driver

Go to the SmartThings mobile app and do a Add device / Scan nearby.
You should see activity in the logging window and a new device called ‘DSC Panel’ should be created in your Devices list in a ‘No room assigned’ room.
Go to the device details screen of the new panel device and tap the 3 vertical dots in the upper right corner, then tap Settings.

**Warning: Because of a SmartThings platform bug in Settings, YOU MUST WAIT a minimum of 15 seconds between each settings change.  If you don't, your setting change may get ignored or set to something erroneous and/or your zones will not get created.**

1. FIRST, if you have multiple partitions, set the Additional Partition field to the ADDITIONAL partitions you need (1 to 7). A new panel device will be created for each additional partition configured.  If you have a single partition, leave this field alone.
2. NEXT, tap on each zone you want to configure and select the appropriate type. Note that you will not be able to change this once the zone device is created. As you configure each zone, a new SmartThings device will be created and appear in your no-room-assigned room. You should also see associated activity in your log window.
3. When you are done configuring your zones, set your 4-6 digit DSC Alarm Code
4. If your Envisalink login password is the default ‘user’, you can leave that field alone, otherwise change it to whatever password you have set for your Envisalink
5. **LASTLY**, set your Envisalink LAN Address (ip:port). Once you make this change, the driver will attempt to go out and connect to your Envisalink. Watch the log messages. If it is able to connect it will then log in with the configured Envisalink password. If for some reason it fails to connect, then it will keep retrying every 15 seconds or so.
Once you’ve successfully connected to the Envisalink, a refresh is issued to update the states of each of your zones.  At this point, you should be able to explore your newly created devices which should be reflecting the current DSC zone and partition status.

*Note: Due to some current issues in the Edge beta, some device states may not fully initialize at startup (e.g. zone bypass state, panel arm switches), however an alarm arm/disarm sequence should resolve this.*


### Updating the Driver
If there is an update pushed to your hub for the Envisalink Edge driver, the DSC devices originally created will not have to be re-created and you do not need to perfom a device-add/scan-nearby again.  When the updated driver is installed, it will automatically re-synch with the Envisalink.

## Using the SmartThings Devices in the Mobile App

The first thing you will want to do after your DSC devices are created is to group them into a room representing your DSC alarm system and modify the zone device names to your liking.

### Zone Devices
The zone devices have no action buttons on the dashboard view - just the status of the device (open/closed, motion/no motion, etc.). On the details screen, you'll see a zone status field, which most of the time will show the open/close-type state of the device, but may also show other status such as alarm, trouble, etc. Also on the details screen is a toggle button you can use to turn on and off bypass state for the zone. 

See additional info below regarding **alarms**.

### Partition Panel Device(s)
The panel device has a bit more function. The button on the *dashboard* view is used to arm or disarm the partition. Whether it performs an arm-away or arm-stay is configured on the details screen (explained below). The state shown on the dashboard is whatever the DSC is reporting such as ready, not ready, exit delay, armed-away or armed-stay, alarm, etc. 

The panel device *detail* screen has a number of features. First is the partition status - same as what is shown on the dashboard. Below that is an 'Indicators' field which will show additional (led) status items such as Trouble, Memory, Bypass, and Fire. Next are discrete buttons to arm-stay or arm-away (or disarm afterwards). Then there is a button to bring up a list of additional (less-used) partition commands that can be invoked. Finally there is a toggle button to configure what happens when you tap the button on the dashboard card. It can be set to either type=arm-away or type=arm-stay, whichever you prefer. Remember you can always go to the details screen to explicitly arm either way, no matter how the dashboard button is configured.

### Alarms
When an alarm occurs, the panel device dashboard view state will show "ALARM!!". The zone(s) that caused the alarm condition will show alarm status on the zone device *detail* screen (the zone device *dashboard* card will continue to show the current state, i.e. open, motion, smoke, etc.). When the alarm is cleared (system is disarmed), the panel state will return to normal ('Ready'), and the Indicators field on the panel details screen will show 'Memory' until the next system arm. For the zone that had caused the alarm, its device *details* screen will continue to show an alarm status until the next time the system is armed. This implements the DSC 'memory' function, giving you a way to see what zone had caused the alarm even after the alarm is cleared on the panel.

## Automations
Automations is preferred since it makes conditions and actions selection easy and straightforward, however webCoRE can also be used.
To control the alarm system from a webCoRE piston, use setPartitionCommand with one of the following for the parameter value:
```
armstay
armaway
disarm
panicfire
panicamb
panicpolice
instantarm
toggleinstant
togglenight
togglechime
refresh
reset
```

## Known Issues

- The Additional Partition Commands that you can select from the panel device details screen are in random order (Edge issue)
- Settings field changes may result in multiple duplicate notifications to the driver (Edge issue); temporary workaround is 15 second wait between changes
- Switches and status attributes may not get initially set correctly when devices are first created (Edge issue).  However they will eventually correct themselves as DSC updates are received, and/or an arm/disarm cycle is completed 
- Incorrect or no state shown in SmartThings app (dashboard) for smoke detectors (and possibly CO as well) due to known SmartThings issue
