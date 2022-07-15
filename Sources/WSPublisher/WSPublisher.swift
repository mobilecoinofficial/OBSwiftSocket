//
//  WSPublisher.swift
//  
//
//  Created by Edon Valdman on 7/8/22.
//

import Foundation
import Combine

public class WebSocketPublisher: NSObject {
    public var connectionData: WSConnectionData? = nil
    
    private var webSocketTask: URLSessionWebSocketTask? = nil
    
    private let _subject = PassthroughSubject<Event, Error>()
    
    public var publisher: AnyPublisher<Event, Error> {
        _subject.eraseToAnyPublisher()
    }
    
    private var observers = Set<AnyCancellable>()
    
    public override init() {
        super.init()
    }
    
    public var password: String? {
        return connectionData?.password
    }
    
    public func connect(using connectionData: WSConnectionData) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session.webSocketTask(with: connectionData.url!)
        
        webSocketTask?.resume()
        self.connectionData = connectionData
    }
    
    public func disconnect(with closeCode: URLSessionWebSocketTask.CloseCode? = nil, reason: String? = nil) {
        webSocketTask?.cancel(with: closeCode ?? .normalClosure,
                             reason: (reason ?? "Closing connection").data(using: .utf8))
        clearTaskData()
    }
    
    private func clearTaskData() {
        webSocketTask = nil
        connectionData = nil
        observers.forEach { $0.cancel() }
        print("Task data cleared")
    }
    
    private func send(_ message: URLSessionWebSocketTask.Message) -> AnyPublisher<Void, Error> {
        guard let task = webSocketTask else {
            return Fail(error: WSErrors.noActiveConnection)
                .eraseToAnyPublisher()
        }
        
        return task.send(message)
//            .mapError { $0 as! WSErrors }
            .eraseToAnyPublisher()
    }
    
    public func send(_ message: String) -> AnyPublisher<Void, Error> {
        return send(.string(message))
    }
    
    public func send(_ message: Data) -> AnyPublisher<Void, Error> {
        return send(.data(message))
    }
    
    public func ping() -> AnyPublisher<Void, Error> {
        guard let task = webSocketTask else {
            return Fail(error: WSErrors.noActiveConnection)
                .eraseToAnyPublisher()
        }
        
        return task.sendPing()
            .eraseToAnyPublisher()
    }
    
    private func startListening() {
        guard let task = webSocketTask else { return }
        
        task.receiveOnce()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] result in
//                print("*1* Stopped listening:", result)
                guard case .finished = result else { return }
                self?.startListening()
            }, receiveValue: { [weak self] message in
//                print("Received message:", message)
                switch message {
                case .data(let d):
                    self?._subject.send(.data(d))
                case .string(let str):
//                        if let obj = try? JSONDecoder.decode(UntypedMessage.self, from: str) {
//                            self?.subject.send(.untyped(obj))
//                        } else {
                    self?._subject.send(.string(str))
//                        }
                @unknown default:
                    self?._subject.send(.generic(message))
                }
            })
            .store(in: &observers)
    }
}

// MARK: - Publishers.WSPublisher: URLSessionWebSocketDelegate

// https://betterprogramming.pub/websockets-in-swift-using-urlsessions-websockettask-bc372c47a7b3
extension WebSocketPublisher: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
//        connectionInProgress = true
        let event = WSEvent.connected(`protocol`)
//        print("Opened session:", event)
        _subject.send(event)
        startListening()
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        clearTaskData()
        
        let reasonStr = reason != nil ? String(data: reason!, encoding: .utf8) : nil
        let event = WSEvent.disconnected(closeCode, reasonStr)
//        print("*2* Closed session:", closeCode.rawValue, reasonStr)
        _subject.send(event)
    }
}

// MARK: - Companion Types

extension WebSocketPublisher {
    /// WebSocket Event
    public enum WSEvent {
        case publisherCreated
        case connected(_ protocol: String?)
        case disconnected(_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: String?)
        case data(Data)
        case string(String)
        case generic(URLSessionWebSocketTask.Message)
        //    case cancelled
    }
    
    public struct WSConnectionData: Codable {
        public init(scheme: String = "ws", ipAddress: String, port: Int, password: String?) {
            self.scheme = scheme
            self.ipAddress = ipAddress
            self.port = port
            self.password = password
        }
        
        public var scheme: String = "ws"
        public var ipAddress: String
        public var port: Int
        public var password: String?
        
        public init?(fromUrl url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme,
                  let ipAddress = components.host,
                  let port = components.port else { return nil }
            
            self.scheme = scheme
            self.ipAddress = ipAddress
            self.port = port
            
            let path = components.path.replacingOccurrences(of: "/", with: "")
            self.password = path.isEmpty ? nil : path
        }
        
        public var urlString: String {
            var str = "\(scheme)://\(ipAddress):\(port)"
            if let pass = password, !pass.isEmpty {
                str += "/\(pass)"
            }
            return str
        }
        
        public var url: URL? {
            return URL(string: urlString)
        }
    }
    
    public enum WSErrors: Error {
        case noActiveConnection
    }
}

// TODO: (real) Publisher type should store the UUID of the observer so it can be cancelled later
// MARK: - URLSessionWebSocketTask Combine

public extension URLSessionWebSocketTask {
    func send(_ message: Message) -> Future<Void, Error> {
        return Future { promise in
            self.send(message) { error in
                if let err = error {
                    promise(.failure(err))
                } else {
                    promise(.success(()))
                }
            }
        }
    }
    
    func sendPing() -> Future<Void, Error> {
        return Future { promise in
            self.sendPing { error in
                if let err = error {
                    promise(.failure(err))
                } else {
                    promise(.success(()))
                }
            }
        }
    }
    
    func receiveOnce() -> Future<URLSessionWebSocketTask.Message, Error> {
        return Future { promise in
            self.receive(completionHandler: promise)
        }
    }
}

extension URLSessionWebSocketTask.Message {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.data(let sentData), .data(let dataToSend)):
            return sentData == dataToSend
        case (.string(let sentStr), .string(let strToSend)):
            return sentStr == strToSend
        default:
            return false
        }
    }
}
