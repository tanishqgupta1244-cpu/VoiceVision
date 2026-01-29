import Foundation

enum WalletAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from wallet service"
        case .server(let message):
            return message
        }
    }
}

struct AddFundsResponse: Decodable {
    let balance: Double
}

struct BalanceResponse: Decodable {
    let balance: Double
}

struct SendMoneyResponse: Decodable {
    let balance: Double
}

final class WalletAPIService {
    static let shared = WalletAPIService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getBalance(completion: @escaping (Result<BalanceResponse, Error>) -> Void) {
        let url = BackendConfig.baseURL.appendingPathComponent("balance")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        performRequest(request, responseType: BalanceResponse.self, completion: completion)
    }

    func addFunds(amount: Int, description: String, completion: @escaping (Result<AddFundsResponse, Error>) -> Void) {
        let url = BackendConfig.baseURL.appendingPathComponent("add-funds")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AddFundsRequest(amount: amount, description: description)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        performRequest(request, responseType: AddFundsResponse.self, completion: completion)
    }
    
    func sendMoney(amount: Int, recipientPhone: String, description: String, completion: @escaping (Result<SendMoneyResponse, Error>) -> Void) {
        let url = BackendConfig.baseURL.appendingPathComponent("send-money")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = SendMoneyRequest(amount: amount, recipientPhone: recipientPhone, description: description)
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        performRequest(request, responseType: SendMoneyResponse.self, completion: completion)
    }

    private func performRequest<T: Decodable>(_ request: URLRequest, responseType: T.Type, completion: @escaping (Result<T, Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(WalletAPIError.invalidResponse)) }
                return
            }

            let responseData = data ?? Data()
            if (200...299).contains(httpResponse.statusCode) {
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: responseData)
                    DispatchQueue.main.async { completion(.success(decoded)) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }

            if let serverError = try? JSONDecoder().decode(ServerErrorResponse.self, from: responseData) {
                DispatchQueue.main.async { completion(.failure(WalletAPIError.server(serverError.error))) }
                return
            }

            DispatchQueue.main.async { completion(.failure(WalletAPIError.invalidResponse)) }
        }.resume()
    }
}

private struct AddFundsRequest: Encodable {
    let amount: Int
    let description: String
}

private struct SendMoneyRequest: Encodable {
    let amount: Int
    let recipientPhone: String
    let description: String
}

private struct ServerErrorResponse: Decodable {
    let error: String
}
