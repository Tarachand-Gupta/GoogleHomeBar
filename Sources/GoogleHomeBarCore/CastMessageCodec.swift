import Foundation

public enum CastNamespace: String, Sendable {
    case connection = "urn:x-cast:com.google.cast.tp.connection"
    case heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    case receiver = "urn:x-cast:com.google.cast.receiver"
    case media = "urn:x-cast:com.google.cast.media"
}

public struct CastMessage: Equatable, Sendable {
    public enum Payload: Equatable, Sendable {
        case utf8(String)
        case binary(Data)
    }

    public var protocolVersion: UInt64
    public var sourceId: String
    public var destinationId: String
    public var namespace: String
    public var payload: Payload

    public init(
        protocolVersion: UInt64 = 0,
        sourceId: String,
        destinationId: String,
        namespace: String,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.sourceId = sourceId
        self.destinationId = destinationId
        self.namespace = namespace
        self.payload = payload
    }

    public static func json(
        sourceId: String = "sender-0",
        destinationId: String = "receiver-0",
        namespace: CastNamespace,
        object: [String: Any]
    ) throws -> CastMessage {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw CastCodecError.invalidUTF8
        }
        return CastMessage(
            sourceId: sourceId,
            destinationId: destinationId,
            namespace: namespace.rawValue,
            payload: .utf8(text)
        )
    }

    public var utf8String: String? {
        if case .utf8(let s) = payload { return s }
        return nil
    }
}

public enum CastCodecError: Error, Equatable, Sendable {
    case truncatedVarint
    case truncatedField
    case invalidWireType(UInt64)
    case invalidUTF8
    case missingRequiredField(String)
    case frameTooLarge(UInt32)
}

/// Pure-Swift protobuf encoder/decoder for `extensions.api.cast_channel.CastMessage`
/// plus CastV2 4-byte big-endian length-prefixed framing.
public enum CastMessageCodec {
    public static let maxFrameSize: UInt32 = 4 * 1024 * 1024

    public static func encodeFramed(_ message: CastMessage) -> Data {
        let body = encode(message)
        var length = UInt32(body.count).bigEndian
        var framed = Data(capacity: 4 + body.count)
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(body)
        return framed
    }

    public static func decodeFrameLength(from header: Data) throws -> UInt32 {
        guard header.count == 4 else {
            throw CastCodecError.truncatedField
        }
        let length = header.withUnsafeBytes { raw -> UInt32 in
            let b0 = UInt32(raw[0]) << 24
            let b1 = UInt32(raw[1]) << 16
            let b2 = UInt32(raw[2]) << 8
            let b3 = UInt32(raw[3])
            return b0 | b1 | b2 | b3
        }
        guard length <= maxFrameSize else {
            throw CastCodecError.frameTooLarge(length)
        }
        return length
    }

    public static func encode(_ message: CastMessage) -> Data {
        var out = Data()
        appendVarintField(fieldNumber: 1, value: message.protocolVersion, to: &out)
        appendStringField(fieldNumber: 2, value: message.sourceId, to: &out)
        appendStringField(fieldNumber: 3, value: message.destinationId, to: &out)
        appendStringField(fieldNumber: 4, value: message.namespace, to: &out)

        switch message.payload {
        case .utf8(let string):
            appendVarintField(fieldNumber: 5, value: 0, to: &out)
            appendStringField(fieldNumber: 6, value: string, to: &out)
        case .binary(let bytes):
            appendVarintField(fieldNumber: 5, value: 1, to: &out)
            appendBytesField(fieldNumber: 7, value: bytes, to: &out)
        }
        return out
    }

    public static func decode(_ data: Data) throws -> CastMessage {
        var cursor = data.startIndex
        var protocolVersion: UInt64?
        var sourceId: String?
        var destinationId: String?
        var namespace: String?
        var payloadType: UInt64?
        var payloadUTF8: String?
        var payloadBinary: Data?

        while cursor < data.endIndex {
            let tag = try readVarint(from: data, cursor: &cursor)
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch (fieldNumber, wireType) {
            case (1, 0):
                protocolVersion = try readVarint(from: data, cursor: &cursor)
            case (2, 2):
                sourceId = try readString(from: data, cursor: &cursor)
            case (3, 2):
                destinationId = try readString(from: data, cursor: &cursor)
            case (4, 2):
                namespace = try readString(from: data, cursor: &cursor)
            case (5, 0):
                payloadType = try readVarint(from: data, cursor: &cursor)
            case (6, 2):
                payloadUTF8 = try readString(from: data, cursor: &cursor)
            case (7, 2):
                payloadBinary = try readBytes(from: data, cursor: &cursor)
            default:
                try skipField(wireType: wireType, in: data, cursor: &cursor)
            }
        }

        guard let sourceId else { throw CastCodecError.missingRequiredField("source_id") }
        guard let destinationId else { throw CastCodecError.missingRequiredField("destination_id") }
        guard let namespace else { throw CastCodecError.missingRequiredField("namespace") }

        let resolvedType = payloadType ?? (payloadBinary != nil ? 1 : 0)
        let payload: CastMessage.Payload
        if resolvedType == 1 {
            payload = .binary(payloadBinary ?? Data())
        } else {
            payload = .utf8(payloadUTF8 ?? "")
        }

        return CastMessage(
            protocolVersion: protocolVersion ?? 0,
            sourceId: sourceId,
            destinationId: destinationId,
            namespace: namespace,
            payload: payload
        )
    }

    // MARK: - Protobuf Primitives

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while true {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
                data.append(byte)
            } else {
                data.append(byte)
                break
            }
        }
    }

    private static func appendVarintField(fieldNumber: UInt64, value: UInt64, to data: inout Data) {
        appendVarint((fieldNumber << 3) | 0, to: &data)
        appendVarint(value, to: &data)
    }

    private static func appendStringField(fieldNumber: UInt64, value: String, to data: inout Data) {
        appendBytesField(fieldNumber: fieldNumber, value: Data(value.utf8), to: &data)
    }

    private static func appendBytesField(fieldNumber: UInt64, value: Data, to data: inout Data) {
        appendVarint((fieldNumber << 3) | 2, to: &data)
        appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    private static func readVarint(from data: Data, cursor: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.endIndex {
            let byte = data[cursor]
            cursor = data.index(after: cursor)
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift >= 64 {
                throw CastCodecError.truncatedVarint
            }
        }
        throw CastCodecError.truncatedVarint
    }

    private static func readBytes(from data: Data, cursor: inout Data.Index) throws -> Data {
        let len = try readVarint(from: data, cursor: &cursor)
        guard len <= UInt64(data.distance(from: cursor, to: data.endIndex)) else {
            throw CastCodecError.truncatedField
        }
        let end = data.index(cursor, offsetBy: Int(len))
        let slice = Data(data[cursor..<end])
        cursor = end
        return slice
    }

    private static func readString(from data: Data, cursor: inout Data.Index) throws -> String {
        let bytes = try readBytes(from: data, cursor: &cursor)
        guard let str = String(data: bytes, encoding: .utf8) else {
            throw CastCodecError.invalidUTF8
        }
        return str
    }

    private static func skipField(wireType: UInt64, in data: Data, cursor: inout Data.Index) throws {
        switch wireType {
        case 0:
            _ = try readVarint(from: data, cursor: &cursor)
        case 1:
            guard data.distance(from: cursor, to: data.endIndex) >= 8 else {
                throw CastCodecError.truncatedField
            }
            cursor = data.index(cursor, offsetBy: 8)
        case 2:
            _ = try readBytes(from: data, cursor: &cursor)
        case 5:
            guard data.distance(from: cursor, to: data.endIndex) >= 4 else {
                throw CastCodecError.truncatedField
            }
            cursor = data.index(cursor, offsetBy: 4)
        default:
            throw CastCodecError.invalidWireType(wireType)
        }
    }
}
