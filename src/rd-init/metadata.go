package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"github.com/goccy/go-yaml"
	"golang.org/x/sys/unix"
)

// Load /mnt/lima-cidata/meta-data
func LoadMetadata(ctx context.Context) ([]string, error) {
	var metaData struct {
		LocalHostName string `yaml:"local-hostname"`
	}

	file, err := os.Open("/mnt/lima-cidata/meta-data")
	if err != nil {
		return nil, fmt.Errorf("failed to load meta-data file: %w", err)
	}
	defer file.Close()
	if err := yaml.NewDecoder(file).DecodeContext(ctx, &metaData); err != nil {
		return nil, fmt.Errorf("failed to unmarshal meta-data file: %w", err)
	}
	slog.InfoContext(ctx, "setting host name", "hostname", metaData.LocalHostName)
	if err := unix.Sethostname([]byte(metaData.LocalHostName)); err != nil {
		return nil, fmt.Errorf("failed to set hostname: %w", err)
	}
	return nil, nil
}
