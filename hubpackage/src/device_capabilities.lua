local partitionstatus = [[
{
    "id": "partyvoice23922.partitionStatus",
    "version": 1,
    "status": "proposed",
    "name": "Partition Status",
    "attributes": {
        "partStatus": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 16
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setPartStatus",
            "enumCommands": []
        }
    },
    "commands": {
        "setPartStatus": {
            "name": "setPartStatus",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 16
                    }
                }
            ]
        }
    }
}
]]

local dscdashswitch = [[
{
    "id": "partyvoice23922.dscdashswitch",
    "version": 1,
    "status": "proposed",
    "name": "dscdashswitch",
    "attributes": {
        "switch": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setSwitch",
            "enumCommands": []
        }
    },
    "commands": {
        "setSwitch": {
            "name": "setSwitch",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string"
                    }
                }
            ]
        }
    }
}
]]

local ledstatus = [[
{
    "id": "partyvoice23922.ledStatus",
    "version": 1,
    "status": "proposed",
    "name": "LED Status",
    "attributes": {
        "ledStatus": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 30
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setledStatus",
            "enumCommands": []
        }
    },
    "commands": {
        "setledStatus": {
            "name": "setledStatus",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 30
                    }
                }
            ]
        }
    }
}
]]

local dscstayswitch = [[
{
    "id": "partyvoice23922.dscstayswitch",
    "version": 1,
    "status": "proposed",
    "name": "dscstayswitch",
    "attributes": {
        "switch": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setSwitch",
            "enumCommands": []
        }
    },
    "commands": {
        "setSwitch": {
            "name": "setSwitch",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string"
                    }
                }
            ]
        }
    }
}
]]

local dscawayswitch = [[
{
    "id": "partyvoice23922.dscawayswitch",
    "version": 1,
    "status": "proposed",
    "name": "dscawayswitch",
    "attributes": {
        "switch": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setSwitch",
            "enumCommands": []
        }
    },
    "commands": {
        "setSwitch": {
            "name": "setSwitch",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string"
                    }
                }
            ]
        }
    }
}
]]

local partitioncommand = [[
{
    "id": "partyvoice23922.partitioncommand",
    "version": 1,
    "status": "proposed",
    "name": "partitionCommand",
    "attributes": {
        "partitionCommand": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 16
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setPartitionCommand",
            "enumCommands": []
        }
    },
    "commands": {
        "setPartitionCommand": {
            "name": "setPartitionCommand",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 16
                    }
                }
            ]
        }
    }
}
]]

local dscselectswitch = [[
{
    "id": "partyvoice23922.dscselectswitch",
    "version": 1,
    "status": "proposed",
    "name": "dscselectswitch",
    "attributes": {
        "switch": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setSwitch",
            "enumCommands": []
        }
    },
    "commands": {
        "setSwitch": {
            "name": "setSwitch",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string"
                    }
                }
            ]
        }
    }
}
]]

local contactstatus = [[
{
    "id": "partyvoice23922.contactstatus",
    "version": 1,
    "status": "proposed",
    "name": "contactStatus",
    "attributes": {
        "contactStatus": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 16
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setContactStatus",
            "enumCommands": []
        }
    },
    "commands": {
        "setContactStatus": {
            "name": "setContactStatus",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 16
                    }
                }
            ]
        }
    }
}
]]

local motionstatus = [[
{
    "id": "partyvoice23922.motionstatus",
    "version": 1,
    "status": "proposed",
    "name": "motionStatus",
    "attributes": {
        "motionStatus": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 16
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setMotionStatus",
            "enumCommands": []
        }
    },
    "commands": {
        "setMotionStatus": {
            "name": "setMotionStatus",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 16
                    }
                }
            ]
        }
    }
}
]]

local zonebypass = [[
{
    "id": "partyvoice23922.zonebypass",
    "version": 1,
    "status": "proposed",
    "name": "zoneBypass",
    "attributes": {
        "zoneBypass": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 16
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setZoneBypass",
            "enumCommands": []
        }
    },
    "commands": {
        "setZoneBypass": {
            "name": "setZoneBypass",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string",
                        "maxLength": 16
                    }
                }
            ]
        }
    }
}
]]

return {
	partitionstatus = partitionstatus,
	dscdashswitch = dscdashswitch,
	ledstatus = ledstatus,
	dscstayswitch = dscstayswitch,
	dscawayswitch = dscawayswitch,
	partitioncommand = partitioncommand,
	dscselectswitch = dscselectswitch,
	contactstatus = contactstatus,
	motionstatus = motionstatus,
	zonebypass = zonebypass,
}
