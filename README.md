# SmartThings Edge Device Driver for DSC/Envisalink

**NOTE:  THIS DRIVER IS WORK-IN-PROGRESS**

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
- SmartThings CLI with Edge authorizations (https://github.com/SmartThingsCommunity/smartthings-cli/tree/master/packages/cli#smartthings-devicespresentation-id)

### Migrating from Alarmserver
This package does not prereq the Alarmserver package.  However if the user already has that running, there is a setup option where you can run both solutions in parallel.  You must be running the latest Alarmserver package from Ralph Torchia (https://github.com/rtorchia/DSC-Envisalink/tree/master/alarmserver), to ensure a functioning proxy server.  Then when configuring the Edge driver per instructions below, you can point the Edge driver to the IP address and port of the Alarmserver proxy server, which will provide a passthrough to the Envisalink.  When you are happy with everything functioning with the new Edge driver configuration, you can change its IP configuration to point directly to the Envisalink device and shutdown Alarmserver.

### Caveats
- This package should be considered beta-level
- No testing has been done yet for smoke, carbon monoxide (co), or water zones (looking for volunteers)
- No testing has been done yet for multi-partition systems (looking for volunteers)
- SmartThings Edge is still in beta as of September 2021

## Setup Instructions

### Clone this repository to a local machine

`cd ~`

`git clone git@github.com:toddaustin07/edge_envisalink.git`

### Configure the Driver
Edit **edge_envisalink/hubpackage/src/config.lua** with the following information (follow Lua table syntax; don't change anything other than the following)
  1) Names associated with any defined DSC user codes (optional)
  2) IP address of Envisalink device on your local LAN -or- of a running Alarmserver package with functioning proxy server (see 'Migrating...' above)
  3) Port number of above (default is '4025')
  4) Password of above (default is 'user')
  5) Your 4-digit alarmcode
  6) Names to associate with each partition panel (or leave default)
  7) Zone information (name, type, associated partition); type can be 'contact', 'motion', 'smoke', 'co', or 'water'
     
     *Hint: keep name short so it fits on the SmartThings mobile app device dashboard card*
     
CAVEAT:  Configuration may change considerably.  I am exploring the use of device SETTINGS, which has the potential to replace the need for a custom configuration file.  However that functionality is still problematic with the current Edge beta.

### Install the Envisalink Edge Driver to your hub

#### Create a Driver Channel and enroll with your hub

*Skip this step if you already have a Driver Channel*

`smartthings edge:channels:create -i <my_channel>.json`

`smartthings edge:channels:enroll [<hubID>]`

#### Create an Edge package for the Envisalink driver
`smartthings edge:drivers:package ~/edge_envisalink/hubpackage`

#### Install to your hub
`smartthings edge:channels:assign <driverID>`

`smartthings edge:drivers:install [<hubID>]`

## Logging
To monitor the driver log messages, run the logger: 

`smartthings edge:drivers:logcat <driverID> --hub-address=<hub_IP_addr>:9495`

Here you will see all messages to and from the Envisalink, as well as other driver logging output and SmartThings platform messages.  Running the logger is not required once everything is up and running to your satisfaction.

*Note: you won't see anything being logged until you peform the next step.*

## Initializing the Driver
First, be sure that you have started logging in a window that you can monitor.

Go into the SmartThings mobile app and tap on the **+** in the upper right corner to **Add**, then tap on **Devices**.  Next, tap on **Scan nearby** in the lower right corner.  At this point the driver will create devices for your partition panel + zones.  Once they are successfully created and initialized, the driver will attempt connection with the Envisalink.  Watch the log messages to be sure it successfully connected and logged in.  Once logged into the Envisalink, the driver then issues a refresh command to the Envisalink to get updates on all your zones and partitions so it can update SmartThings.  At this point, you should be able to explore your newly created devices which should be reflecting the current DSC zone and partition status.

### Reinstalling the Driver
If there is any reason you need to re-install the Envisalink Edge driver, the DSC devices originally created will not have to be re-created and you do not need to perfom a device-add/scan-nearby again.  When the driver is (re)installed, it will automatically re-synch with the Envisalink.

## Using the SmartThings Devices in the Mobile App

The first thing you will want to do after your DSC devices are created is to group them into a room.

### Zone Devices
The zone devices have no action buttons on the dashboard view - just the status of the device (open/closed, motion/no motion, etc.). On the details screen, you'll see a zone status field, which most of the time will show the open/close-type state of the device, but may also show other status such as alarm, trouble, etc. Also on the details screen is a toggle button you can use to turn on and off bypass state for the zone. 

See additional info below regarding alarms.

### Partition Panel Device
The panel device has a bit more function. The button on the dashboard view is used to arm or disarm the partition. Whether it performs an arm-away or arm-stay is configured on the details screen (explained below). The state shown on the dashboard is whatever the DSC is reporting such as ready, not ready, exit delay, armed-away or armed-stay, alarm, etc. I have eliminated the force-ready status since it's not very useful and in the old Alarmserver implementation always caused a crazy amount of constant state changes, filling up the log and messages everytime someone opened a door or walked by a motion sensor!

The panel device detail screen has a number of features. First is the partition status - same as what is shown on the dashboard. Below that is an 'Indicators' field which will show additional status items such as Trouble, Memory, Bypass, and Fire. Next are discrete buttons to arm-stay or arm-away (or disarm afterwards). Then there is a button to bring up a list of additional (less-used) partition commands that can be invoked. Finally there is a toggle button to configure what happens when you tap the button on the dashboard card. It can be set to either type=arm-away or type=arm-stay, whichever you prefer. Remember you can always go to the details screen to directly arm either way, no matter how the dashboard button is configured.

### Alarms
When an alarm occurs, the panel device dashboard view state will show "ALARM!!". The zone(s) that caused the alarm condition will show alarm status on the zone device **DETAILS** screen (the zone device dashboard card will continue to show the current state, i.e. open, motion, smoke, etc.). When the alarm is cleared (system is disarmed), the panel state will return to normal ('Ready'), and the Indicators field on the details screen will show 'Memory' until the next system arm. For the zone that alarmed, its device details screen will continue to show an alarm status until the next time the system is armed. This implements the DSC 'memory' function, giving you a way to see what zone caused the alarm even after the alarm is cleared.

### Panel Device Settings
Selected driver configuration settings can be updated through the mobile app, rather than editing the Lua configuration file and reinstalling the driver to the hub.

Go to the (primary) panel device details screen in the mobile app.  Then tap the 3 vertical dots in the upper right corner.  You should then see a number of options including Edit, Settings, Driver, and Information.  Tap Settings.  Here you will see the configuration settings you can change, which includes Envisalink IP:port address, Envisalink login password, and 4-digit DSC alarm code.  

If you enter a new Envisalink IP:port address, if it is valid, the driver will disconnect and then try to re-connect to the Envisalink at that new address.

Note: it is on this Settings screen where you might, in the future, be able to configure your partitions and zones rather than using a configuration file; however this capability  is not yet functioning.
