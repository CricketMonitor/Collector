#!/bin/bash

# Build script for Cricket Monitor Performance Collector

set -e

echo "Building Cricket Monitor Performance Collector..."

# Clean previous builds
rm -f cricket-collector
rm -f cricket-collector-*

# Build for current platform
go build -o cricket-collector main.go

# Build for common Linux architectures
echo "Building for Linux amd64..."
GOOS=linux GOARCH=amd64 go build -o cricket-collector-linux-amd64 main.go

echo "Building for Linux arm64..."
GOOS=linux GOARCH=arm64 go build -o cricket-collector-linux-arm64 main.go

echo "Building for Linux 386..."
GOOS=linux GOARCH=386 go build -o cricket-collector-linux-386 main.go

echo "Build completed successfully!"
echo ""
echo "Binaries created:"
ls -la cricket-collector*

echo ""
echo "Usage:"
echo "  1. Copy .env.example to .env and configure your settings"
echo "  2. Run: ./cricket-collector"
echo ""
echo "Or set environment variables directly:"
echo "  CRICKET_API_KEY=your_key ./cricket-collector"