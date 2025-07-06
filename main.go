package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

type Config struct {
	APIBaseURL      string
	APIKey          string
	ServerName      string
	CollectInterval int
	Debug           bool
}

type MetricsPayload struct {
	// Server registration fields
	ServerName      string            `json:"server_name"`
	Hostname        string            `json:"hostname"`
	IPAddress       string            `json:"ip_address,omitempty"`
	OperatingSystem string            `json:"operating_system"`
	Architecture    string            `json:"architecture"`
	Tags            map[string]string `json:"tags,omitempty"`
	
	// Metrics fields
	Timestamp             string  `json:"timestamp"`
	CPUUsagePercent       float64 `json:"cpu_usage_percent"`
	CPULoad1m             float64 `json:"cpu_load_1m"`
	CPULoad5m             float64 `json:"cpu_load_5m"`
	CPULoad15m            float64 `json:"cpu_load_15m"`
	MemoryUsagePercent    float64 `json:"memory_usage_percent"`
	MemoryUsedBytes       uint64  `json:"memory_used_bytes"`
	MemoryTotalBytes      uint64  `json:"memory_total_bytes"`
	MemoryAvailableBytes  uint64  `json:"memory_available_bytes"`
	SwapUsedBytes         uint64  `json:"swap_used_bytes"`
	SwapTotalBytes        uint64  `json:"swap_total_bytes"`
	DiskUsagePercent      float64 `json:"disk_usage_percent"`
	DiskUsedBytes         uint64  `json:"disk_used_bytes"`
	DiskTotalBytes        uint64  `json:"disk_total_bytes"`
	DiskAvailableBytes    uint64  `json:"disk_available_bytes"`
	DiskReadBytes         uint64  `json:"disk_read_bytes"`
	DiskWriteBytes        uint64  `json:"disk_write_bytes"`
	DiskReadOps           uint64  `json:"disk_read_ops"`
	DiskWriteOps          uint64  `json:"disk_write_ops"`
	DiskIOTime            uint64  `json:"disk_io_time"`
	NetworkRXBytes        uint64  `json:"network_rx_bytes"`
	NetworkTXBytes        uint64  `json:"network_tx_bytes"`
	NetworkRXPackets      uint64  `json:"network_rx_packets"`
	NetworkTXPackets      uint64  `json:"network_tx_packets"`
	NetworkRXErrors       uint64  `json:"network_rx_errors"`
	NetworkTXErrors       uint64  `json:"network_tx_errors"`
	
	// Per-disk information
	DiskDevices           []DiskDevice `json:"disk_devices,omitempty"`
}

type DiskDevice struct {
	Device          string  `json:"device"`
	Mountpoint      string  `json:"mountpoint"`
	Filesystem      string  `json:"filesystem"`
	UsagePercent    float64 `json:"usage_percent"`
	UsedBytes       uint64  `json:"used_bytes"`
	TotalBytes      uint64  `json:"total_bytes"`
	AvailableBytes  uint64  `json:"available_bytes"`
	ReadBytes       uint64  `json:"read_bytes,omitempty"`
	WriteBytes      uint64  `json:"write_bytes,omitempty"`
	ReadOps         uint64  `json:"read_ops,omitempty"`
	WriteOps        uint64  `json:"write_ops,omitempty"`
}

func main() {
	// Load environment variables
	godotenv.Load()

	config := Config{
		APIBaseURL:      getEnv("CRICKET_API_URL", "http://localhost:3002"),
		APIKey:          getEnv("CRICKET_API_KEY", ""),
		ServerName:      getEnv("CRICKET_SERVER_NAME", ""),
		CollectInterval: getEnvInt("CRICKET_COLLECT_INTERVAL", 60),
		Debug:           getEnvBool("CRICKET_DEBUG", false),
	}

	if config.APIKey == "" {
		log.Fatal("CRICKET_API_KEY environment variable is required")
	}

	if config.ServerName == "" {
		hostname, err := os.Hostname()
		if err != nil {
			log.Fatal("Failed to get hostname and CRICKET_SERVER_NAME not set:", err)
		}
		config.ServerName = hostname
	}

	log.Printf("Starting Cricket Performance Collector")
	log.Printf("API URL: %s", config.APIBaseURL)
	log.Printf("Server Name: %s", config.ServerName)
	log.Printf("Collection Interval: %d seconds", config.CollectInterval)

	// Start metrics collection loop
	ticker := time.NewTicker(time.Duration(config.CollectInterval) * time.Second)
	defer ticker.Stop()

	// Collect metrics immediately on startup
	collectAndSendMetrics(config)

	// Then collect on interval
	for range ticker.C {
		collectAndSendMetrics(config)
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}


func collectAndSendMetrics(config Config) {
	payload, err := collectSystemMetrics(config)
	if err != nil {
		log.Printf("Error collecting metrics: %v", err)
		return
	}

	if config.Debug {
		log.Printf("Collected metrics: CPU=%.2f%%, Memory=%.2f%%, Disk=%.2f%%", 
			payload.CPUUsagePercent, payload.MemoryUsagePercent, payload.DiskUsagePercent)
		log.Printf("Memory details: Used=%d bytes (%.1f GB), Total=%d bytes (%.1f GB), Available=%d bytes (%.1f GB)",
			payload.MemoryUsedBytes, float64(payload.MemoryUsedBytes)/(1024*1024*1024),
			payload.MemoryTotalBytes, float64(payload.MemoryTotalBytes)/(1024*1024*1024),
			payload.MemoryAvailableBytes, float64(payload.MemoryAvailableBytes)/(1024*1024*1024))
		log.Printf("Swap details: Used=%d bytes (%.1f GB), Total=%d bytes (%.1f GB)",
			payload.SwapUsedBytes, float64(payload.SwapUsedBytes)/(1024*1024*1024),
			payload.SwapTotalBytes, float64(payload.SwapTotalBytes)/(1024*1024*1024))
	}

	if err := sendMetrics(config, payload); err != nil {
		log.Printf("Error sending metrics: %v", err)
	}
}

func collectSystemMetrics(config Config) (*MetricsPayload, error) {
	hostname, _ := os.Hostname()
	hostInfo, _ := host.Info()

	payload := &MetricsPayload{
		// Server information for auto-registration
		ServerName:      config.ServerName,
		Hostname:        hostname,
		OperatingSystem: hostInfo.OS,
		Architecture:    runtime.GOARCH,
		Tags: map[string]string{
			"collector": "cricket-go-collector",
			"version":   "1.0.0",
		},
		
		// Metrics
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	// CPU metrics
	cpuPercent, err := cpu.Percent(time.Second, false)
	if err == nil && len(cpuPercent) > 0 {
		payload.CPUUsagePercent = cpuPercent[0]
	}

	// Load average
	loadAvg, err := load.Avg()
	if err == nil {
		payload.CPULoad1m = loadAvg.Load1
		payload.CPULoad5m = loadAvg.Load5
		payload.CPULoad15m = loadAvg.Load15
	}

	// Memory metrics
	memInfo, err := mem.VirtualMemory()
	if err == nil {
		payload.MemoryUsagePercent = memInfo.UsedPercent
		payload.MemoryUsedBytes = memInfo.Used
		payload.MemoryTotalBytes = memInfo.Total
		payload.MemoryAvailableBytes = memInfo.Available
	}

	// Swap metrics
	swapInfo, err := mem.SwapMemory()
	if err == nil {
		payload.SwapUsedBytes = swapInfo.Used
		payload.SwapTotalBytes = swapInfo.Total
	}

	// Disk metrics (root filesystem)
	diskInfo, err := disk.Usage("/")
	if err == nil {
		payload.DiskUsagePercent = diskInfo.UsedPercent
		payload.DiskUsedBytes = diskInfo.Used
		payload.DiskTotalBytes = diskInfo.Total
		payload.DiskAvailableBytes = diskInfo.Free
	}
	
	// Per-disk information
	diskDevices := []DiskDevice{}
	// Get I/O stats for devices (do this once, use for both per-disk and totals)
	diskIOStats, _ := disk.IOCounters()
	
	partitions, err := disk.Partitions(false) // false = only physical devices
	if err == nil {
		
		if config.Debug {
			log.Printf("Found %d partitions", len(partitions))
		}
		
		for _, partition := range partitions {
			// Skip special filesystems
			if partition.Fstype == "tmpfs" || partition.Fstype == "devtmpfs" || 
			   partition.Fstype == "sysfs" || partition.Fstype == "proc" ||
			   partition.Fstype == "devpts" || partition.Fstype == "securityfs" ||
			   partition.Fstype == "cgroup" || partition.Fstype == "cgroup2" ||
			   partition.Fstype == "overlay" {
				continue
			}
			
			// Get usage stats for this partition
			usage, err := disk.Usage(partition.Mountpoint)
			if err != nil {
				if config.Debug {
					log.Printf("Skipping %s: %v", partition.Mountpoint, err)
				}
				continue
			}
			
			device := DiskDevice{
				Device:         partition.Device,
				Mountpoint:     partition.Mountpoint,
				Filesystem:     partition.Fstype,
				UsagePercent:   usage.UsedPercent,
				UsedBytes:      usage.Used,
				TotalBytes:     usage.Total,
				AvailableBytes: usage.Free,
			}
			
			// Try to match with I/O stats
			// Clean device name for I/O stats lookup
			deviceName := strings.TrimPrefix(partition.Device, "/dev/")
			
			// Try different device name variations for I/O stats
			ioStatNames := []string{
				deviceName,                    // e.g., "sda1"
				strings.TrimRight(deviceName, "0123456789"), // e.g., "sda" from "sda1"
			}
			
			for _, name := range ioStatNames {
				if ioStat, exists := diskIOStats[name]; exists {
					device.ReadBytes = ioStat.ReadBytes
					device.WriteBytes = ioStat.WriteBytes
					device.ReadOps = ioStat.ReadCount
					device.WriteOps = ioStat.WriteCount
					break
				}
			}
			
			diskDevices = append(diskDevices, device)
			
			if config.Debug {
				log.Printf("Added disk: %s (%s) -> %s, %.1f%% used", 
					device.Device, device.Filesystem, device.Mountpoint, device.UsagePercent)
			}
		}
		
		if config.Debug {
			log.Printf("Collected %d disk devices", len(diskDevices))
		}
	}
	payload.DiskDevices = diskDevices

	// Disk I/O metrics (aggregate totals - reuse the diskIOStats we already fetched)
	if diskIOStats != nil {
		// Sum up all disk devices
		var totalReadBytes, totalWriteBytes, totalReadOps, totalWriteOps, totalIOTime uint64
		for _, ioStat := range diskIOStats {
			totalReadBytes += ioStat.ReadBytes
			totalWriteBytes += ioStat.WriteBytes
			totalReadOps += ioStat.ReadCount
			totalWriteOps += ioStat.WriteCount
			totalIOTime += ioStat.IoTime
		}
		payload.DiskReadBytes = totalReadBytes
		payload.DiskWriteBytes = totalWriteBytes
		payload.DiskReadOps = totalReadOps
		payload.DiskWriteOps = totalWriteOps
		payload.DiskIOTime = totalIOTime
	}

	// Network metrics
	netStats, err := net.IOCounters(false)
	if err == nil && len(netStats) > 0 {
		payload.NetworkRXBytes = netStats[0].BytesRecv
		payload.NetworkTXBytes = netStats[0].BytesSent
		payload.NetworkRXPackets = netStats[0].PacketsRecv
		payload.NetworkTXPackets = netStats[0].PacketsSent
		payload.NetworkRXErrors = netStats[0].Errin
		payload.NetworkTXErrors = netStats[0].Errout
	}

	return payload, nil
}

func sendMetrics(config Config, payload *MetricsPayload) error {
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal metrics: %w", err)
	}

	req, err := http.NewRequest("POST", config.APIBaseURL+"/api/metrics/ingest", bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+config.APIKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send metrics: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("metrics submission failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}