export declare class PortManager {
    findAvailablePort(startPort?: number): Promise<number>;
    private isPortAvailable;
}
