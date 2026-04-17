import Foundation

struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let message: String?
    let data: T?
}

struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let pagination: Pagination
}

struct Pagination: Decodable, Sendable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case total
        case totalPages = "total_pages"
    }
}

struct EmptyData: Decodable, Sendable {}
