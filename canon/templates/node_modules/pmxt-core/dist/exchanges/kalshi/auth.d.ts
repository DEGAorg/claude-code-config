import { ExchangeCredentials } from '../../BaseExchange';
/**
 * Manages Kalshi authentication using RSA-PSS signatures.
 * Reference: https://docs.kalshi.com/getting_started/quick_start_authenticated_requests
 */
export declare class KalshiAuth {
    private credentials;
    constructor(credentials: ExchangeCredentials);
    private validateCredentials;
    /**
     * Generates the required headers for an authenticated request.
     *
     * @param method The HTTP method (e.g., "GET", "POST").
     * @param path The request path (e.g., "/trade-api/v2/portfolio/orders").
     * @returns An object containing the authentication headers.
     */
    getHeaders(method: string, path: string): Record<string, string>;
    /**
     * Signs the request using RSA-PSS.
     * The message to sign is: timestamp + method + path
     */
    private signRequest;
}
