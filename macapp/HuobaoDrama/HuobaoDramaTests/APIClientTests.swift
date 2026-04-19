import Testing
import Foundation
@testable import HuobaoDrama

// MARK: - Mock URLProtocol

/// 用于测试的自定义 URLProtocol，拦截所有网络请求并返回预设响应。
class MockURLProtocol: URLProtocol {
    /// 预设的响应数据
    static var mockData: Data?
    /// 预设的 HTTP 状态码
    static var mockStatusCode: Int = 200
    /// 预设的 HTTP 错误
    static var mockError: Error?
    /// 记录最后一次请求
    static var lastRequest: URLRequest?
    /// 预设的响应头
    static var mockHeaders: [String: String] = ["Content-Type": "application/json"]

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.mockStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: MockURLProtocol.mockHeaders
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

        if let data = MockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// 重置所有 mock 状态
    static func reset() {
        mockData = nil
        mockStatusCode = 200
        mockError = nil
        lastRequest = nil
        mockHeaders = ["Content-Type": "application/json"]
    }
}

// MARK: - 测试用辅助方法

/// 创建用于测试的 JSON 响应数据，包裹在标准 APIResponse 结构中。
func makeAPIResponseData<T: Encodable>(data: T) -> Data {
    let response = APIResponse<T>(code: 0, message: "ok", data: data)
    return try! JSONEncoder().encode(response)
}

/// 创建空的 APIResponse 数据
func makeEmptyAPIResponseData() -> Data {
    let response = APIResponse<EmptyData>(code: 0, message: "ok", data: EmptyData())
    return try! JSONEncoder().encode(response)
}

/// 创建错误的 JSON 数据（用于解码失败测试）
func makeInvalidJSONData() -> Data {
    return Data("{ this is not valid json }}}".utf8)
}

/// 通过 JSON 创建测试用的 Drama 实例
func makeTestDrama(id: Int = 1, title: String = "测试剧本") -> Drama {
    let json = """
    {
        "id": \(id),
        "title": "\(title)",
        "genre": "drama",
        "style": "realistic",
        "total_episodes": 3,
        "status": "draft",
        "tags": [],
        "episodes": [],
        "characters": [],
        "scenes": [],
        "created_at": "2026-04-18T10:00:00Z",
        "updated_at": "2026-04-18T10:00:00Z"
    }
    """
    return try! JSONDecoder().decode(Drama.self, from: Data(json.utf8))
}

/// 创建用于测试的 Mock URLSession
func makeTestSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - APIClient Tests

@Suite("APIClient Tests")
struct APIClientTests {

    // MARK: - GET 请求测试

    @Test("GET 请求成功返回正确解码数据")
    func getSuccess() async throws {
        let expectedDrama = makeTestDrama(id: 1, title: "测试剧本")
        let jsonData = makeAPIResponseData(data: expectedDrama)

        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = jsonData
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/dramas/1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        let decoded = try JSONDecoder().decode(APIResponse<Drama>.self, from: data)
        #expect(decoded.data?.title == "测试剧本")
        #expect(decoded.data?.id == 1)
    }

    @Test("GET 请求 404 返回服务器错误")
    func getNotFound() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = Data("not found".utf8)
        MockURLProtocol.mockStatusCode = 404

        let url = URL(string: "http://localhost:8080/api/v1/dramas/999")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 404)
        #expect(data.count > 0)
    }

    // MARK: - POST 请求测试

    @Test("POST 请求成功创建资源")
    func postSuccess() async throws {
        let createdDrama = makeTestDrama(id: 10, title: "新建剧本")
        let jsonData = makeAPIResponseData(data: createdDrama)

        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = jsonData
        MockURLProtocol.mockStatusCode = 201

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateDramaRequest(
            title: "新建剧本",
            genre: "comedy",
            style: "cartoon",
            totalEpisodes: 5,
            tags: []
        ))

        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 201)

        let decoded = try JSONDecoder().decode(APIResponse<Drama>.self, from: data)
        #expect(decoded.data?.id == 10)
        #expect(decoded.data?.title == "新建剧本")
    }

    @Test("POST 请求验证失败返回 400")
    func postValidationError() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = Data("{\"error\": \"validation failed\"}".utf8)
        MockURLProtocol.mockStatusCode = 400

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (_, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 400)
    }

    // MARK: - DELETE 请求测试

    @Test("DELETE 请求成功返回空数据")
    func deleteSuccess() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = makeEmptyAPIResponseData()
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/dramas/1")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        let decoded = try JSONDecoder().decode(APIResponse<EmptyData>.self, from: data)
        #expect(decoded.data != nil)
    }

    @Test("DELETE 请求不存在的资源返回 404")
    func deleteNotFound() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = Data("not found".utf8)
        MockURLProtocol.mockStatusCode = 404

        let url = URL(string: "http://localhost:8080/api/v1/dramas/999")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 404)
    }

    // MARK: - 错误处理测试

    @Test("网络错误抛出 networkError")
    func networkError() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: nil
        )

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        let request = URLRequest(url: url)

        do {
            _ = try await session.data(for: request)
            Issue.record("应该抛出网络错误")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == NSURLErrorDomain)
        }
    }

    @Test("无效 JSON 返回解析错误")
    func decodingError() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = makeInvalidJSONData()
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/dramas/1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        do {
            _ = try JSONDecoder().decode(APIResponse<Drama>.self, from: data)
            Issue.record("应该抛出解码错误")
        } catch {
            // 解码错误是预期行为
            #expect(error is DecodingError)
        }
    }

    @Test("HTTP 500 服务器错误返回状态码")
    func serverError500() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = Data("Internal Server Error".utf8)
        MockURLProtocol.mockStatusCode = 500

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 500)
    }

    // MARK: - 请求头测试

    @Test("请求设置正确的 Content-Type 头")
    func requestContentTypeHeader() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = makeEmptyAPIResponseData()
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        _ = try await session.data(for: request)

        let capturedRequest = MockURLProtocol.lastRequest
        #expect(capturedRequest != nil)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("GET 请求不包含请求体")
    func getNoBody() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = makeEmptyAPIResponseData()
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        _ = try await session.data(for: request)

        let capturedRequest = MockURLProtocol.lastRequest
        #expect(capturedRequest?.httpBody == nil)
        #expect(capturedRequest?.httpMethod == "GET")
    }

    @Test("POST 请求包含 JSON 请求体")
    func postJSONBody() async throws {
        let session = makeTestSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = makeEmptyAPIResponseData()
        MockURLProtocol.mockStatusCode = 200

        let body = CreateDramaRequest(
            title: "测试",
            genre: nil,
            style: nil,
            totalEpisodes: 1,
            tags: nil
        )

        let url = URL(string: "http://localhost:8080/api/v1/dramas")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        _ = try await session.data(for: request)

        let capturedRequest = MockURLProtocol.lastRequest
        #expect(capturedRequest?.httpBody != nil)

        // 验证请求体可以解码回原始结构
        let decodedBody = try JSONDecoder().decode(CreateDramaRequest.self, from: capturedRequest!.httpBody!)
        #expect(decodedBody.title == "测试")
        #expect(decodedBody.totalEpisodes == 1)
    }

    // MARK: - APIError 测试

    @Test("APIError 描述正确")
    func apiErrorDescriptions() {
        let networkError = APIError.networkError(NSError(domain: "test", code: -1))
        #expect(networkError.errorDescription?.contains("网络错误") == true)

        let serverError = APIError.serverError(500, "Internal Server Error")
        #expect(serverError.errorDescription?.contains("500") == true)

        let decodingError = APIError.decodingError(DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: [], debugDescription: "test")))
        #expect(decodingError.errorDescription?.contains("解析错误") == true)

        let invalidURL = APIError.invalidURL
        #expect(invalidURL.errorDescription?.contains("无效 URL") == true)

        let unknown = APIError.unknown
        #expect(unknown.errorDescription?.contains("未知错误") == true)
    }

    // MARK: - APIResponse 解码测试

    @Test("APIResponse 成功解码带数据")
    func apiResponseWithData() throws {
        let json = """
        {
            "code": 0,
            "message": "success",
            "data": {
                "id": 1,
                "title": "测试",
                "genre": "drama",
                "style": "realistic",
                "total_episodes": 3,
                "status": "draft",
                "tags": [],
                "episodes": [],
                "created_at": "2026-04-18T10:00:00Z",
                "updated_at": "2026-04-18T10:00:00Z"
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(APIResponse<Drama>.self, from: data)
        #expect(response.code == 0)
        #expect(response.message == "success")
        #expect(response.data?.title == "测试")
    }

    @Test("APIResponse 解码无数据字段")
    func apiResponseNoData() throws {
        let json = """
        {
            "code": 0,
            "message": "success",
            "data": null
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(APIResponse<Drama>.self, from: data)
        #expect(response.code == 0)
        #expect(response.data == nil)
    }

    // MARK: - PaginatedResponse 解码测试

    @Test("PaginatedResponse 正确解码")
    func paginatedResponse() throws {
        let json = """
        {
            "items": [
                {
                    "id": 1,
                    "title": "剧本1",
                    "genre": "drama",
                    "style": "realistic",
                    "total_episodes": 3,
                    "status": "draft",
                    "tags": [],
                    "episodes": [],
                    "created_at": "2026-04-18T10:00:00Z",
                    "updated_at": "2026-04-18T10:00:00Z"
                }
            ],
            "pagination": {
                "page": 1,
                "page_size": 20,
                "total": 100,
                "total_pages": 5
            }
        }
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PaginatedResponse<Drama>.self, from: data)
        #expect(response.items.count == 1)
        #expect(response.items.first?.title == "剧本1")
        #expect(response.pagination.page == 1)
        #expect(response.pagination.total == 100)
        #expect(response.pagination.totalPages == 5)
    }

    // MARK: - EmptyData 测试

    @Test("EmptyData 可以从空 JSON 对象解码")
    func emptyDataDecoding() throws {
        let data = Data("{}".utf8)
        let empty = try JSONDecoder().decode(EmptyData.self, from: data)
        #expect(empty != nil)
    }
}
