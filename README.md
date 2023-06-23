# SmartThings Edge Device Driver for DSC/Envisalink

*06/20/23 UPDATE: Version 3.0 of the driver has now been released and this README has been updated to reflect the changes.*

This Edge driver is targeted to users having a DSC security system with an Envisalink board connecting it to the local LAN.  Edge drivers run directly on a SmartThings hub.  The driver will connect with the Envisalink to create and update devices reflecting your DSC system partition panels and zones.

*PLEASE NOTE:  This driver only works with DSC systems.  Those with Honeywell or Honeywell-compatable systems should check out an applicable driver [here](https://community.smartthings.com/t/st-edge-honeywell-ademco-vista-panel-envisalink/233766).*


### Old 'Alarmserver' Users
Some may already have an existing solution using the 'Alarmserver' package. Alarmserver is a Python-based program that runs on a LAN-connected computer (often a Raspberry Pi) and connects to an Envisalink module to pass messages back and forth to SmartThings.  However Alarmserver is based on the legacy DTH / SmartApp / graph callback implementation which is being sunset by SmartThings.  This driver provides a migration path for those Alarmserver users and offers a number of additional benefits as outlined below.


### Benefits
- Eliminates dependency on Groovy DTHs, which has been sunset
- No SmartApp is required
- Leverages 100% local execution of Edge platform (including related automations)
- For old Alarmserver users: 
  - Eliminates need for separate stay / away panel devices
  - Eliminates need for separate computer to run Envisalink interfacing code
  - Can be run in parallel with existing Alarmserver setup for low risk transition

### Pre-requisites
- SmartThings hub V2 or later
- **DSC** security system
- Connected and running Envisalink interface (know its IP address and port number)

### Migrating from Alarmserver
This package does not prereq the Alarmserver package.  However if the user already has that running, there is a setup option where you can run both solutions in parallel.  You must be running the latest Alarmserver package from Ralph Torchia (https://github.com/rtorchia/DSC-Envisalink/tree/master/alarmserver), to ensure a functioning proxy server.  Then when configuring the Edge driver per instructions below, you can point the Edge driver to the IP address and port of the Alarmserver proxy server, which will provide a passthrough to the Envisalink.  When you are happy with everything functioning with the new Edge driver configuration, you can change its IP configuration to point directly to the Envisalink device and shutdown Alarmserver.

## Setup Instructions

### Install the Envisalink Edge Driver to your hub
Use this [channel invite](https://bestow-regional.api.smartthings.com/invite/d429RZv8m9lo).

Sign in to SmartThings, enroll your hub to the channel, list the available drivers, and select to install '**Envisalink 3.0**'.
  
### Initialize and Configure the Driver

Go to the SmartThings mobile app and do an *Add device / Scan for nearby devices*.
A new device called ‘DSC Primary Panel’ should be created in the SmartThings room where your hub device is located.
Go to the device Controls screen of the new panel device and tap the 3 vertical dots in the upper right corner, then tap Settings.

1. FIRST, if you have multiple partitions, set the Additional Partition field to the ADDITIONAL number of partitions you need (1 to 7 more). A new panel device will be created for each additional partition configured.  If you have a single partition, leave this field alone.
2. NEXT, tap on each zone you want to configure and select the appropriate type. Note that you will not be able to change this once the zone device is created, so proceed carefully. As you define each zone, a new SmartThings device will be created.
3. When you are done configuring your zones, set your 4-6 digit DSC Alarm Code.  This code will be used by the driver whenever you arm/disarm the system through SmartThings.  Be sure it is one that has been configured in your DSC system; it can be the system master code, or any of the additional user codes.
4. If your Envisalink login password is the default ‘user’, you can leave that field alone, otherwise change it to whatever password you have set for your Envisalink.  Note that this password is *not* your EyesOn web application password.
5. Other Settings options are available, which can be configured later and are described later in this document.
6. **LASTLY**, set your Envisalink LAN Address (ip:port). Once you make this change, the driver will attempt to go out and connect to your Envisalink. If it is able to connect it will then log in with the configured Envisalink password. If for some reason it fails to connect, then it will keep retrying every 15 seconds or so.
Once you’ve successfully connected to the Envisalink, a refresh is issued to update the states of each of your zones and panel(s).  At this point, you should be able to explore your newly created devices which should be reflecting the current DSC zone and partition status.

### Updating the Driver
If there is an update pushed to your hub for the Envisalink Edge driver, the DSC devices originally created will not have to be re-created and you do not need to perfom an *Add device* again.  When the updated driver is installed, it will automatically re-synch with the Envisalink.

## Using the SmartThings Devices in the Mobile App

The first thing you will want to do after your DSC devices are created is to group them into a room representing your DSC alarm system and modify the zone device names to your liking.

### Zone Devices
The zone devices have no action buttons on the dashboard view - just the status of the device (open/closed, motion/no motion, etc.). On the Controls screen, you'll see a zone status field, which most of the time will show the open/close-type state of the device, but may also show other status such as alarm, trouble, etc. Also on the details screen is a toggle button you can use to turn on and off bypass state for the zone. 

See additional info below regarding **alarms**.

### Partition Panel Device(s)
The panel device has a bit more function. The button on the *dashboard* view is used to arm or disarm the partition. Whether it performs an arm-away or arm-stay is configured on the Controls screen (explained below). The state shown on the dashboard is whatever the DSC partition is reporting such as Ready, Not ready, Exit delay, Armed-away or Armed-stay, Alarm, Offline, etc. 

The panel device *Controls* screen has a number of fields:

#### Partition status
This is same value as what is shown on the dashboard, which reflects the overall state of the partition. 

#### Most recent user
The field is used to display the name associated with the arm code that was last used to arm/disarm the system *from a physical DSC panel device*.  

You can configure a map of names back in the Settings screen of the panel device.  Look for the 'Accesscode->Name Map' field.  Here you provide a comma-separated list of access code 'slots' that have been configured for your DSC system.  Slot 40 is always the 'Master' code, but you may have configured your DSC system for additional user access codes 01-32.  For example, if you, your wife, and kids each have their own code, you can configure this field like this:
  ```
  40=Master, 01=Hubby, 02=Wifey, 03=Kids
  ```
  * This of course this is assuming you have configured your DSC system with those three user access codes.
  * Note that you can use any configured access code you choose (master or user) for the one this driver uses to arm/disarm ('Access Code for Arm/Disarm' field in panel device Settings)

#### Indicators
This will show additional (panel LED) status items such as Trouble, Memory, Bypass, and Fire.

#### Trouble type
When the partition is in a Trouble state, this field will display the specific trouble being reported by the system, such as Battery, Bell, AC Power Lost, etc.

*Special info regarding AC Power Lost detection:  DSC systems have by default a 30 minute delay before an 'AC Power Lost' trouble type is reported.  In the meantime a generic 'Service Required' trouble type may be displayed.  To have an AC Power Lost reported immediately, the user will have to program section 377 Communication Variables of the DSC system, and setting 'AC Failure Communication Delay' to 0*

#### Arm Stay, Arm Away
These buttons are provided to arm the partition (or disarm afterwards) for either away or stay mode. 

#### Additional partition commands
This is a button to bring up a list of additional (less-used) partition commands that can be invoked. 

#### Alarm type
This field is used to provide a SmartThings-standard alarm state whenever the DSC system is alarming.  It is a standard SmartThings capability, but for this driver it will only show either 'Off' or 'Siren'.  Tapping any of the buttons has no effect; it is used for 'output' only to trigger automations.

#### Configure dashboard button arm type
This button is used to configure what happens when you tap the button on the panel device's **dashboard** card. It can be set to either type=arm-away or type=arm-stay, whichever you prefer. Remember you can always go to the Controls screen to explicitly arm either way, no matter how the dashboard button is configured.

### Alarms
When an alarm occurs, the panel device dashboard view state will show "ALARM!!". The zone(s) that caused the alarm condition will show alarm status on the zone device *Controls* screen (the zone device *dashboard* card will continue to show the current state, i.e. open, motion, smoke, etc.). When the alarm is cleared (when the system is disarmed), the panel state will return to normal ('Ready'), and the Indicators field on the panel Controls screen will show 'Memory' until the next system arm. For the zone that had caused the alarm, its device *Controls* screen will continue to show an alarm status until the next time the system is armed. This implements the DSC 'memory' function, giving you a way to see what zone had caused the alarm even after the alarm is cleared on the panel.

## Automations
Defining automation routines using the SmartThings app is easiest since it makes conditions and actions selection easy and straightforward, however Rules can also be used.

### Rules
To define your rules JSON, following are examples of the most common partition triggers/commands:

#### To trigger from partition state
* component:  main
* capability:  partyvoice23922.partitionstatus3a
* attribute: partStatus
* values:
```
Armed-away
Armed-away (instant)
Armed-stay
Armed-stay (instant)
Disarmed
Ready
Entry delay
Exit delay
ALARM!!
Offline
```

#### To trigger from trouble type
* component:  main
* capability:  partyvoice23922.dsctroubletype3a
* attribute: troubleType
* values:
```
AC Power Lost
Battery
Bell
Failure to Communicate
Loss of Time
Service Required
Sensor/Zone Fault
Sensor/Zone Tamper
Sensor/Zone Battery
Telephone Line Fault
```

#### To issue partition commands

* component:  main
* capability:  partyvoice23922.partitioncommand3
* command: setPartitionCommand
* values:
```
armstay
armaway
disarm
panicfire
panicamb
panicpolice
instantstay
instantaway
togglenight
togglechime
refresh
reset
pgm1
pgm2
pgm3
pgm4
```

### Enisalink connection monitoring
A new feature in the V3.0 driver is the periodic monitoring of the network connection to the Envisalink.  The frequency of the check can be configured in the primary panel device Settings screen under 'Periodic Connection Check'.  This can be set for as often as every 5 minutes (default is every 15 minutes).  If during this periodic check the Envisalink is not responding, all partition and zone devices will go into an offline state and the partition status will be set to 'Offline', enabling automations to be triggered.  The driver will then continuously try to reconnect with the Envisalink every 15 seconds.  Once connection is re-established, all devices will revert to online status and the partition status will be refreshed with the latest state reported by the DSC.

### Auxilary siren triggering
It is possible to wire your DSC system to an auxilary siren or alarm and trigger it using one of the PGM commands to the DSC.  To support this scenario, the partition device Settings screen includes two fields: one to define an auxilary trigger (PGM1-PGM4), and a second to set the duration for the trigger (in seconds).

### Auto-synching with STHM
Warning: this feature has proven unreliable for many, so use with caution.

You can have your DSC system automatically set whenever SmartThings Home Monitor is armed or disarmed.  Use the 'Set arm mode from STHM' field in the partition device Settings screen to enable or disable this auto-synching.  It is disabled by default.
