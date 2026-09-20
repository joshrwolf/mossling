# Completion protocol v1 and configuration protocol v2

`SyncProtocol.swift` in MosslingCore defines bounded transport values. Persistence and WatchConnectivity remain adapters. Configuration uses its own phone-to-watch latest-context channel; packets below carry completion history bidirectionally.

## Public API

- `SyncPacket.events([CompletionEvent]) -> SyncPacket`
- `SyncPacket.acknowledgment([UUID]) -> SyncPacket` (sorts and deduplicates IDs)
- `SyncPacket.historyRequest(for: [CompletionEvent]) throws -> SyncPacket`
- `packet.encoded() throws -> Data`
- `SyncPacket.decode(Data) throws -> SyncPacket`
- `packet.kind`: `.events`, `.acknowledgment`, `.historyRequest`
- `packet.events`, `.acknowledgedIDs`, `.inventory: SyncInventory?`
- `SyncBatcher.batches(events:) throws -> [SyncPacket]`
- `SyncInventory(events:) throws`, equatable with `eventCount` and `digest`

Use `encoded`/`decode` at transport boundaries, not a separately configured JSON coder. The wire format is version 1, sorted-key JSON with milliseconds-since-epoch dates. Packets are at most 48 KiB and 25 events/acknowledgment IDs. Batches obey both limits and have deterministic order/content, independent of the input ordering. An oversized single event rejects batching explicitly; it is not dropped.

Events are validated as a whole using `CompletionLedger`: any rejected record or duplicate event ID makes the entire packet invalid. A duplicate *delivery* is valid and harmless. Unknown protocol versions, malformed shapes, and oversized data fail closed. Retain the sender's pending events when receiving fails.

Inventories hash sorted canonical event encodings using length-prefixed 64-bit FNV-1a. They detect ordinary differences, including changed data under an existing event ID. They are not a cryptographic integrity or authenticity mechanism. Pass the canonical ledger's unique events, not an unreconciled list.

## Adapter contract

1. Completing a snack atomically commits the event and its pending ID before showing success.
2. Send pending events using `SyncBatcher`, through background transfer; immediate messaging may also send the exact same bytes.
3. On `.events`, merge a decoded/validated packet into the document, persist the complete candidate document, then send `.acknowledgment(packet.events.map(\.eventID))`. Never acknowledge before the durable write succeeds. Duplicate events may be acknowledged again.
4. On `.acknowledgment`, atomically remove only the intersection with local pending IDs. Never delete completion history. Unknown/already-acknowledged IDs are harmless.
5. On activation or explicit sync, each side sends one `.historyRequest(for: localLedger.events)`.
6. On `.historyRequest`, compare the inventory with the local inventory. If different, stream all local ledger events through bounded `SyncBatcher` packets. Do not trigger another history request when receiving events or acknowledgments. Both sides independently issue their activation request, allowing union reconciliation after reinstall or partial history loss.
7. Do not mark historical records pending merely because they were sent for reconciliation. Only originally locally pending IDs require clearing from the outbox. An acknowledgment arriving out of order is safe.

The first history exchange may send redundant records while another exchange is in flight. That is acceptable: union merging is idempotent and no per-packet arrival order is required. The next activation/manual request repairs a failed historical transfer. The durable outbox continues retrying new local completions until acknowledged.

Keep in-flight transport deduplication keyed by exact encoded packet bytes and clear it when a transfer fails/completes or an activation begins. Never keep a permanent sent-packet cache that prevents retry after a receiver loses state. Do not recursively resync upon every receipt.

Configuration authority is separate: only phone sends configuration, watch accepts newer revisions and equal-revision authoritative refreshes, and a newly installed watch may accept the initial revision-zero document. Decode/validate and persist configuration before publishing it. A protocol mismatch should surface an update-needed message without emptying saved progress.

## Known scope boundary

This is a two-device personal sync protocol, not a cloud service or anti-cheat system. The phone and watch may briefly show different growth while disconnected. Permanent progress is a projection of merged completion events and unique reward keys. Sync never adds remote XP totals.

## Configuration upgrades

ConfigurationSnapshot emits and accepts version 2. Older app versions reject this new snapshot rather than silently dropping pause/skip semantics; update phone and Watch together. Save migration from schema 1 preserves history/outbox/authority, but resets the received-configuration flag so the Watch can refresh an equal revision. Only a different previous authority is retired; a refresh must never retire its own phone. Completion packet version and reward identities are unchanged.

Equal-revision snapshots from the same active phone are accepted to restore optional fields an older Watch decoder omitted. Lower revisions and retired authorities remain rejected. This requires the sole phone writer to increment revision for every content change, including future content-changing migrations. Equal-revision replay is otherwise idempotent. Whole-device restoration/downgrade remains outside this authority contract.
