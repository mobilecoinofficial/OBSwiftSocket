//
//  WSPublisher Extensions.swift
//  
//
//  Created by Edon Valdman on 7/9/22.
//

import Foundation
import Combine
import WSPublisher

// MARK: - Send Encodable Objects

extension WebSocketPublisher {
    /// Sending Encodable Objects
    /// - Parameter object: <#object description#>
    /// - Returns: <#description#>
    func send<T: Encodable>(_ object: T) -> Future<Void, Error> {
        guard let json = JSONEncoder.toString(from: object) else {
            return Future { $0(.failure(JSONErrors.failedToEncodeObject)) }
        }
        return send(json)
    }
}

// MARK: - OBS-WS Events

//enum OBSWSEvents {
//    case untyped(_ message: UntypedMessage)
//    case generic(_ message: URLSessionWebSocketTask.Message)
//    //    case cancelled
//}
