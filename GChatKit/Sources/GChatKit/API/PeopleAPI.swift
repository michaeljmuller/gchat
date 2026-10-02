import Foundation

public protocol ProfileService: Sendable {
    /// The signed-in user.
    func me() async throws -> Profile
    /// Looks up a Chat user ("users/123") in the People API.
    func profile(for user: String) async throws -> Profile
    /// The people in the organization's directory.
    func listDirectory() async throws -> [Profile]
}

public struct PeopleAPI: ProfileService {
    private let client: APIClient

    /// Enough for a sidebar list; larger directories are cut off here.
    private static let directoryLimit = 2000

    public init(client: APIClient) {
        self.client = client
    }

    private struct Person: Decodable {
        struct Name: Decodable { var displayName: String? }
        struct Photo: Decodable { var url: String? }
        struct Email: Decodable { var value: String? }
        var resourceName: String?
        var names: [Name]?
        var photos: [Photo]?
        var emailAddresses: [Email]?

        func profile(user: String) -> Profile {
            Profile(
                user: user,
                displayName: names?.first?.displayName,
                photoURL: photos?.first?.url.flatMap(URL.init(string:)),
                email: emailAddresses?.first?.value)
        }
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
        // Chat user IDs and People API person IDs are the same number.
        let id = user.split(separator: "/").last.map(String.init) ?? user
        var components = URLComponents(string: "https://people.googleapis.com/v1/people/\(id)")!
        components.queryItems = [URLQueryItem(name: "personFields", value: "names,photos,emailAddresses")]
        let person: Person = try await client.send("GET", components.url!)
        return person.profile(user: user)
    }

    public func listDirectory() async throws -> [Profile] {
        struct Page: Decodable {
            var people: [Person]?
            var nextPageToken: String?
        }
        var profiles: [Profile] = []
        var token: String?
        repeat {
            var components = URLComponents(string: "https://people.googleapis.com/v1/people:listDirectoryPeople")!
            components.queryItems = [
                URLQueryItem(name: "readMask", value: "names,photos,emailAddresses"),
                URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let token { components.queryItems?.append(URLQueryItem(name: "pageToken", value: token)) }
            let page: Page = try await client.send("GET", components.url!)
            for person in page.people ?? [] {
                guard let id = person.resourceName?.split(separator: "/").last else { continue }
                profiles.append(person.profile(user: "users/\(id)"))
            }
            token = page.nextPageToken
        } while token?.isEmpty == false && profiles.count < Self.directoryLimit
        return profiles
    }
}
