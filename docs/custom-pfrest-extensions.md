# Custom pfREST extension contracts

pfSense Manager discovers endpoint support from the connected firewall's OpenAPI document at `/api/v2/schema/openapi`.

The features below are not assumed to exist in the standard pfREST installation. They are enabled only when the selected profile's schema reports the exact method and path shown here. A compatible extension may implement a subset of these operations.

## Remote diagnostics

| Feature | Method | Path |
| --- | --- | --- |
| Traceroute | `POST` | `/api/v2/diagnostics/traceroute` |
| DNS lookup | `POST` | `/api/v2/diagnostics/dns_lookup` |

Traceroute accepts the request fields currently used by the application: `host` and `max_hops`. DNS lookup accepts `host` and `type`.

## SMART drive status

| Feature | Method | Path |
| --- | --- | --- |
| SMART status | `GET` | `/api/v2/diagnostics/smart_status` |

The response should return a `data` list containing drive records. Missing SMART support does not disable system temperature, memory or swap monitoring.

## Configuration export

| Feature | Method | Path |
| --- | --- | --- |
| XML configuration backup | `GET` | `/api/v2/system/config` |

The response body is treated as raw configuration bytes. The operation must enforce appropriate read permissions because the exported configuration can contain sensitive firewall settings.

## pfBlockerNG

| Feature | Method | Path |
| --- | --- | --- |
| Read status | `GET` | `/api/v2/status/pfblockerng` |
| Enable or pause | `PATCH` | `/api/v2/status/pfblockerng` |
| Update lists | `POST` | `/api/v2/status/pfblockerng/update` |

The status operation controls whether the pfBlockerNG screen can open. Update and enable controls are independently disabled when their operations are absent.

## Captive portal

| Feature | Method | Path |
| --- | --- | --- |
| List sessions | `GET` | `/api/v2/services/captiveportal/sessions` |
| Disconnect a session | `DELETE` | `/api/v2/services/captiveportal/session` |
| List vouchers | `GET` | `/api/v2/services/captiveportal/vouchers` |
| Generate vouchers | `POST` | `/api/v2/services/captiveportal/vouchers` |

Sessions and vouchers are evaluated independently. A firewall can therefore expose read-only sessions, read-only vouchers, or the complete management contract.

## Capability states

- **Available:** the selected profile's OpenAPI schema reports the exact operation.
- **Unsupported:** schema discovery succeeded, but the operation is absent. The related action is disabled before a request is sent.
- **Unknown:** schema discovery could not complete because access was forbidden, authentication failed, the schema endpoint was unavailable, the response was invalid, or the request failed temporarily. The application explains the limitation and permits a direct attempt for compatibility with restricted installations.

An endpoint request returning `403` remains a permission failure. It is not converted into an unsupported-feature result. Timeouts and network failures also remain temporary connection failures.

Capability snapshots are held in memory and scoped to the active firewall profile. Switching profiles or ending the session discards the previous snapshot.

Maintained by privacyOG.
