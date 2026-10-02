import Foundation

public protocol ProfileService: Sendable {
    /// The signed-in user.
    func me() async throws -> Profile
    /// Looks up a Chat user ("users/123") in the People API.
    func profile(for user: String) async throws -> Profile
}

public struct PeopleAPI: ProfileService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func me() async throws -> Profile {
        struct UserInfo: Decodable {
            var sub: String
            var name: String?
            var picture: String?
            var email: String?
        }
        let info: UserInfo = try await client.send(
            "GET", URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        return Profile(
            user: "users/\(info.sub)", displayName: info.name,
            photoURL: info.picture.flatMap(URL.init(string:)), email: info.email)
    }

    public func profile(for user: String) async throws -> Profile {
        struct Person: Decodable {
            struct Name: Decodable { var displayName: String? }
            struct Photo: Decodable { var url: String? }
            struct Email: Decodable { var value: String? }
            var names: [Name]?
            var photos: [Photo]?
            var emailAddresses: [Email]?
        }
        // Chat user IDs and People API person IDs are the same number.
        let id = user.split(separator: "/").last.map(String.init) ?? user
        var components = URLComponents(string: "https://people.googleapis.com/v1/people/\(id)")!
        components.queryItems = [URLQueryItem(name: "personFields", value: "names,photos,emailAddresses")]
        let person: Person = try await client.send("GET", components.url!)
        return Profile(
            user: user,
            displayName: person.names?.first?.displayName,
            photoURL: person.photos?.first?.url.flatMap(URL.init(string:)),
            email: person.emailAddresses?.first?.value)
    }
}
