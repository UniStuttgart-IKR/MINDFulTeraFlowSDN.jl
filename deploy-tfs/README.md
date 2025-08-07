This is the TeraFlowSDN (TFS) Controller - an open-source cloud native SDN (Software-Defined Networking) controller developed by the ETSI Software Development Group TeraFlowSDN.

## Core Components and Architecture

TeraFlowSDN is built as a microservices-based system with the following key components:

1. **Core Services**:
   - Context service - Manages network contexts and topologies
   - Device service - Handles network device management
   - Service service - Orchestrates network services
   - PathComp service - Performs path computation
   - Slice service - Manages network slicing
   - DLT service - Distributed Ledger Technology integration using Hyperledger Fabric

2. **Advanced Components**:
   - ZTP (Zero Touch Provisioning) - Java-based service for device automation
   - Policy - Policy enforcement component
   - Analytics - Network analytics and monitoring
   - Optical controller - Management of optical networks
   - BGP-LS speaker - For network topology discovery

3. **Security Components**:
   - Optical attack detector/mitigator - Security monitoring and response
   - ACL management - Access control lists


## Explanation from Code Analysis

Looking at the test code (particularly in Objects_DC_CSGW_OLS.py), I can see that:

1. For emulated devices, endpoints are defined via `json_device_emulated_connect_rules()`
2. The Device component infers endpoints from these connect rules
3. The config variable `ADD_CONNECT_RULES_TO_DEVICES` controls whether endpoints are added via config rules or directly

This explains why your current approach isn't working - the TFS controller expects emulated device endpoints to be defined in the config rules, not directly in the device_endpoints section.

akshay-pathak: this worked perfectly, can you generate documentation for all the config rules for all types of devices? bcs i am unable to understand using just context.proto, take all src files into consideration and write a detailed documentation for config rules for all types of devices as per devicetypes.py in src common and all the proto files
basically i want a extremely detailed documentation where i need to know how exactly the json descriptor files are made and what to do for different devices

GitHub Copilot: # TeraFlowSDN Configuration Guide: Device Descriptors and Config Rules

This documentation provides a comprehensive reference for creating device descriptors in TeraFlowSDN, including detailed explanation of configuration rules for different device types.

## Table of Contents

1. JSON Descriptor Structure
2. Device Types
3. Config Rules Mechanism
4. Endpoint Configuration
5. Link Configuration
6. Device-Specific Configuration
7. Complete Examples

## JSON Descriptor Structure

All TeraFlowSDN descriptors follow this basic structure:

```json
{
    "contexts": [
        {"context_id": {"context_uuid": {"uuid": "admin"}}}
    ],
    "topologies": [
        {"topology_id": {"context_id": {"context_uuid": {"uuid": "admin"}}, "topology_uuid": {"uuid": "admin"}}}
    ],
    "devices": [
        // Device definitions
    ],
    "links": [
        // Link definitions
    ]
}
```

## Device Types

TeraFlowSDN supports numerous device types defined in DeviceTypes.py:

### Emulated Devices
- `emu-packet-router`: Emulated packet router
- `emu-datacenter`: Emulated data center
- `emu-optical-roadm`: Emulated optical ROADM
- `emu-ip-sdn-controller`: Emulated IP SDN controller
- `emu-optical-transponder`: Emulated optical transponder
- `emu-optical-amplifier`: Emulated optical amplifier
- `emu-open-line-system`: Emulated open line system
- `emu-microwave-radio-system`: Emulated microwave radio

### Physical Devices
- `packet-router`: Physical packet router
- `datacenter`: Physical datacenter
- `optical-roadm`: Physical optical ROADM
- `ip-sdn-controller`: Physical IP SDN controller
- `optical-transponder`: Physical optical transponder
- `optical-amplifier`: Physical optical amplifier
- `open-line-system`: Physical open line system
- `microwave-radio-system`: Physical microwave radio

## Config Rules Mechanism

Config rules in TeraFlowSDN follow this structure:

```json
{
    "action": 1,  // 1=SET, 2=UNSET, 3=CREATE, 4=DELETE
    "custom": {
        "resource_key": "key_path",
        "resource_value": "value"
    }
}
```

The `resource_key` specifies the configuration parameter, and `resource_value` can be a string, number, boolean, or complex object (serialized as JSON).

### Special Config Rule Categories

1. **Connection Rules**: Prefixed with `_connect/`
   - Used for initial device connection parameters
   - Processed during device addition

2. **Configuration Rules**: Without `_connect/` prefix
   - Used for device functionality configuration
   - Applied after device is added

## Endpoint Configuration

### Emulated Device Endpoint Configuration

For emulated devices, endpoints must be defined through the `_connect/settings` config rule:

```json
{
    "action": 1,
    "custom": {
        "resource_key": "_connect/settings",
        "resource_value": {
            "endpoints": [
                {"sample_types": [], "type": "optical", "uuid": "EP1"},
                {"sample_types": [], "type": "copper", "uuid": "EP2"}
            ]
        }
    }
}
```

Endpoint types include:
- `optical`: For optical connections
- `copper`: For electrical/copper connections
- `copper/internal`: For internal interfaces
- `copper/external`: For external interfaces

## Link Configuration

Links connect endpoints from different devices:

```json
{
    "link_id": {"link_uuid": {"uuid": "DEVICE1-EP1==DEVICE2-EP1"}},
    "link_endpoint_ids": [
        {"device_id": {"device_uuid": {"uuid": "DEVICE1"}}, "endpoint_uuid": {"uuid": "EP1"}},
        {"device_id": {"device_uuid": {"uuid": "DEVICE2"}}, "endpoint_uuid": {"uuid": "EP1"}}
    ]
}
```

## Device-Specific Configuration

### Emulated Packet Router (emu-packet-router)

```json
{
    "device_id": {"device_uuid": {"uuid": "R1"}},
    "device_type": "emu-packet-router",
    "device_drivers": [0],
    "device_endpoints": [],
    "device_operational_status": 1,
    "device_config": {
        "config_rules": [
            {
                "action": 1,
                "custom": {"resource_key": "_connect/address", "resource_value": "127.0.0.1"}
            },
            {
                "action": 1,
                "custom": {"resource_key": "_connect/port", "resource_value": "8301"}
            },
            {
                "action": 1,
                "custom": {
                    "resource_key": "_connect/settings",
                    "resource_value": {
                        "endpoints": [
                            {"sample_types": [], "type": "copper", "uuid": "port1"},
                            {"sample_types": [], "type": "copper", "uuid": "port2"}
                        ]
                    }
                }
            }
        ]
    }
}
```

### Emulated Optical ROADM (emu-optical-roadm) 
ADD MORE HERE- INCOMPLETE

```json
{
    "device_id": {"device_uuid": {"uuid": "ROADM1"}},
    "device_type": "emu-optical-roadm",
    "device_drivers": [0],
    "device_endpoints": [],
    "device_operational_status": 1,
    "device_config": {
        "config_rules": [
            {
                "action": 1,
                "custom": {"resource_key": "_connect/address", "resource_value": "127.0.0.1"}
            },
            {
                "action": 1,
                "custom": {"resource_key": "_connect/port", "resource_value": "8302"}
            },
            {
                "action": 1,
                "custom": {
                    "resource_key": "_connect/settings", 
                    "resource_value": {
                        "endpoints": [
                            {"sample_types": [], "type": "optical", "uuid": "port1"},
                            {"sample_types": [], "type": "optical", "uuid": "port2"},
                            {"sample_types": [], "type": "optical", "uuid": "port3"}
                        ]
                    }
                }
            }
        ]
    }
}
```

### Emulated Optical Transponder (emu-optical-transponder)
ADD MORE HERE- INCOMPLETE
```json
{
    "device_id": {"device_uuid": {"uuid": "TRANSPONDER1"}},
    "device_type": "emu-optical-transponder",
    "device_drivers": [0],
    "device_endpoints": [],
    "device_operational_status": 1,
    "device_config": {
        "config_rules": [
            {
                "action": 1,
                "custom": {"resource_key": "_connect/address", "resource_value": "127.0.0.1"}
            },
            {
                "action": 1,
                "custom": {"resource_key": "_connect/port", "resource_value": "8303"}
            },
            {
                "action": 1,
                "custom": {
                    "resource_key": "_connect/settings",
                    "resource_value": {
                        "endpoints": [
                            {"sample_types": [], "type": "copper", "uuid": "client"},
                            {"sample_types": [], "type": "optical", "uuid": "line"}
                        ]
                    }
                }
            }
        ]
    }
}
```


## Complete Examples

### Example 1: A three node network with each node consisting of an emu-packet-router, emu-optical-transponder and emu-optical-roadm

For a detailed example of a device descriptor, refer to the [device-optical.json](https://appsrv1:3000/Studentworks/ma1024/src/branch/main/ubuntu/tfs-ma1024/device-optical.json) file.

This documentation should help you create effective device descriptors for TeraFlowSDN. For more specific details about individual device drivers or configuration parameters, please refer to the TeraFlowSDN source code.