//
//  NetworkUtilities.swift
//  Subler
//
//  Created by Damiano Galassi on 04/08/2017.
//

import Foundation

// MARK: - URL Utilities

extension String {

    func urlEncoded() -> String {
        return self.precomposedStringWithCompatibilityMapping.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
    }

}

protocol URLSessionTaskDelegate {

}

extension URLSession {

    static func data(from url: URL, httpMethod: String = "GET", httpBody: Data? = nil, header: [String:String] = [:], cachePolicy: URLRequest.CachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy) -> Data? {

        let sem = DispatchSemaphore(value: 0)
        var downloadData : Data? = nil

        URLSession.dataTask(with: url, httpMethod: httpMethod, httpBody: httpBody, header: header, cachePolicy: cachePolicy) { (data) in
            downloadData = data
            sem.signal()
            }.resume()

        _ = sem.wait(timeout: DispatchTime.distantFuture)

        return downloadData
    }

    static func dataTask(with url: URL, httpMethod: String = "GET", httpBody: Data? = nil, header: [String:String] = [:], cachePolicy: URLRequest.CachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy, completionHandler: @escaping (Data?) -> Void) -> URLSessionTask {

        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 30.0)
        request.httpMethod = httpMethod
        request.httpBody = httpBody
        for (key, value) in header {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let session = URLSession.shared
        let task = session.dataTask(with: request) { (data, response, error) in

            if let data = data {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 200 {
                    completionHandler(data)
                }
                else {
                    completionHandler(nil)
                }
            }
            else {
                completionHandler(nil)
            }
        }

        return task
    }

}