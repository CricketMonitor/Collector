# Cricket Monitor Performance Collector

[Monitor your website uptime with CricketMon](https://cricketmon.io)


A lightweight Go application that collects system performance metrics from Linux servers and sends them to the Cricket Monitor Performance API.

## Features

- **Lightweight**: Single binary, minimal resource usage (~5MB memory)
- **System Metrics**: CPU, memory, disk, network, and load average monitoring
- **Auto-registration**: Automatically registers with the API on first run
- **Configurable**: Flexible collection intervals and settings
- **Reliable**: Built-in retry logic and error handling
- **Secure**: API key authentication
- **Production Ready**: Systemd service integration

## Quick Installation

```bash
curl -sSL https://cricketmon.io/install-collector | bash
```

## Manual Installation

### Prerequisites
- Linux system (amd64, arm64, or 386)
- Go 1.21+ (for building from source)
- API key from Cricket Monitor dashboard

### Build from Source
```bash
# Clone or download the collector
git clone https://github.com/your-org/cricket-monitor.git
cd cricket-monitor/collectors/linux-collector

# Install dependencies
go mod tidy

# Build
./build.sh
```

### Configuration

Create a `.env` file or set environment variables:

```bash
# Required
CRICKET_API_URL=https://collector.cricketmon.io
CRICKET_API_KEY=ckt_perf_your_api_key_here

# Optional (defaults to hostname)
CRICKET_SERVER_NAME=my-server
CRICKET_COLLECT_INTERVAL=60
CRICKET_DEBUG=false
```

### Run
```bash
# Direct execution
./cricket-collector

# As systemd service (after installation)
sudo systemctl start cricket-collector
sudo systemctl status cricket-collector
```

## Collected Metrics

### CPU Metrics
- `cpu_usage_percent`: Overall CPU utilization percentage
- `cpu_load_1m`, `cpu_load_5m`, `cpu_load_15m`: System load averages

### Memory Metrics
- `memory_usage_percent`: Memory utilization percentage
- `memory_used_bytes`: Used memory in bytes
- `memory_total_bytes`: Total system memory
- `memory_available_bytes`: Available memory
- `swap_used_bytes`: Used swap space
- `swap_total_bytes`: Total swap space

### Disk Metrics (Root filesystem)
- `disk_usage_percent`: Disk utilization percentage
- `disk_used_bytes`: Used disk space in bytes
- `disk_total_bytes`: Total disk space
- `disk_available_bytes`: Available disk space

### Network Metrics (All interfaces combined)
- `network_rx_bytes`: Bytes received
- `network_tx_bytes`: Bytes transmitted
- `network_rx_packets`: Packets received
- `network_tx_packets`: Packets transmitted
- `network_rx_errors`: Receive errors
- `network_tx_errors`: Transmit errors

## Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `CRICKET_API_URL` | `https://collector.cricketmon.io` | **Required** API endpoint URL |
| `CRICKET_API_KEY` | - | **Required** Account-based authentication token |
| `CRICKET_SERVER_NAME` | hostname | Display name for the server |
| `CRICKET_COLLECT_INTERVAL` | 60 | Collection interval in seconds |
| `CRICKET_DEBUG` | false | Enable debug logging |

## Systemd Service

The installer automatically creates a systemd service:

```bash
# Control the service
sudo systemctl start cricket-collector
sudo systemctl stop cricket-collector
sudo systemctl restart cricket-collector
sudo systemctl status cricket-collector

# Enable/disable auto-start
sudo systemctl enable cricket-collector
sudo systemctl disable cricket-collector

# View logs
sudo journalctl -u cricket-collector -f
```

## Architecture Support

The collector supports multiple Linux architectures:
- **amd64** (x86_64) - Intel/AMD 64-bit
- **arm64** (aarch64) - ARM 64-bit
- **386** (i386) - Intel/AMD 32-bit

## API Integration

The collector automatically:
1. Auto-registers the server on first metrics submission
2. Sends both server info and metrics in each request
3. Handles authentication with account-based API keys
4. Retries failed requests
5. Updates server "last seen" timestamps
6. Uses one API key for all servers in your account

## Security Considerations

- API keys are stored in configuration files with restricted permissions (600)
- The service runs as a dedicated `cricket` user (not root)
- No sensitive system information is collected
- All API communication uses HTTPS
- Rate limiting is handled gracefully

## Troubleshooting

### Check Service Status
```bash
sudo systemctl status cricket-collector
```

### View Logs
```bash
# Recent logs
sudo journalctl -u cricket-collector --no-pager

# Follow logs in real-time
sudo journalctl -u cricket-collector -f

# Debug mode
sudo systemctl edit cricket-collector
# Add: Environment=CRICKET_DEBUG=true
sudo systemctl restart cricket-collector
```

### Test Configuration
```bash
# Test API connectivity
curl -H "Authorization: Bearer $CRICKET_API_KEY" \
     "$CRICKET_API_URL/api/servers"

# Manual run with debug
sudo -u cricket CRICKET_DEBUG=true /opt/cricket-collector/cricket-collector
```

### Common Issues

1. **API Key Invalid**: Check API key in configuration file
2. **Network Connectivity**: Ensure firewall allows outbound HTTPS
3. **Permissions**: Verify `cricket` user has proper permissions
4. **Resource Limits**: Check if system has available memory/CPU

## Resource Usage

The collector is designed to be lightweight:
- **Memory**: ~5MB RAM usage
- **CPU**: <1% CPU on modern systems
- **Network**: ~1KB per metric submission
- **Disk**: Single ~5MB binary

## Development

/note Make sure you have the lateste go. APT may have out-of-date packages


### Dependencies
- `github.com/shirou/gopsutil/v3` - System metrics collection
- `github.com/joho/godotenv` - Environment variable loading


#### Install depdencies with:
```
go mod tidy
```

### Building
```bash
# Development build
go build -o cricket-collector main.go

# Production builds (all architectures)
./build.sh
```

### Testing
```bash
# Run with debug output
CRICKET_DEBUG=true go run main.go

# Test with mock API
CRICKET_API_URL=http://localhost:3002 go run main.go
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
