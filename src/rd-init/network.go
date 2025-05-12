package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"strings"

	"github.com/goccy/go-yaml"
)

var networkConfig struct {
	Version uint `yaml:"version"`
	Ethernets map[string]struct {
		Match struct {
			MACAddress string `yaml:"macaddress"`
		} `yaml:"match"`
		DHCP4 bool `yaml:"dhcp4"`
		SetName string `yaml:"set-name,omitempty"`
		DHCP4Overrides struct {
			RouteMetric uint `yaml:"route-metric"`
		} `yaml:"dhcp4-overrides"`
		DHCPIdentifier string `yaml:"dhcp-identifier"`
		NameServers struct {
			Addresses []net.IP `yaml:"addresses"`
		} `yaml:"nameservers"`
	} `yaml:"ethernets"`
}

func LoadNetworkConfig(ctx context.Context) ([]string, error) {
	hasChanges := false
	file, err := os.Open("/mnt/lima-cidata/network-config")
	if err != nil {
		return nil, fmt.Errorf("failed to read network-config: %w", err)
	}
	defer file.Close()

	if err := yaml.NewDecoder(file).DecodeContext(ctx, &networkConfig); err != nil {
		return nil, fmt.Errorf("failed to unmarshal network-config: %w", err)
	}

	for name, ethernet := range networkConfig.Ethernets {
		if ethernet.SetName != "" {
			if ethernet.Match.MACAddress == "" {
				return nil, fmt.Errorf("network interface %q has set-name=%q but no match", name, ethernet.SetName)
			}
			slog.InfoContext(ctx, "renaming network interface", "name", ethernet.SetName)
			contents := []string {
				"[Match]",
				fmt.Sprintf("MACAddress=%s", ethernet.Match.MACAddress),
				"[Link]",
				"NamePolicy=",
				fmt.Sprintf("Name=%s", ethernet.SetName),
				"",
			}
			outPath := fmt.Sprintf("/run/systemd/network/10-%s.link", name)
			if err := os.WriteFile(outPath, []byte(strings.Join(contents, "\n")), 0o644); err != nil {
				return nil, fmt.Errorf("failed to write link file %s: %w", outPath, err)
			}
			hasChanges = true
		}

		config := make(map[string]map[string]string)
		update := func(section, key, value string) {
			m, ok := config[section]
			if !ok {
				m = make(map[string]string)
				config[section] = m
			}
			m[key] = value
		}

		if ethernet.Match.MACAddress != "" {
			update("Match", "MACAddress", ethernet.Match.MACAddress)
		}
		if ethernet.DHCP4 {
			update("Network", "DHCP", "ipv4")
		}
		if ethernet.DHCP4Overrides.RouteMetric != 0 {
			update("DHCPv4", "RouteMetric", fmt.Sprintf("%d", ethernet.DHCP4Overrides.RouteMetric))
		}
		if ethernet.DHCPIdentifier != "" {
			switch ethernet.DHCPIdentifier {
			case "mac", "duid":
				update("DHCPv4", "ClientIdentifier", ethernet.DHCPIdentifier)
			default:
				return nil, fmt.Errorf("error writing network-config: ethernet %q has invalid DHCP client identifier %q", name, ethernet.DHCPIdentifier)
			}
		}
		if len(ethernet.NameServers.Addresses) > 0 {
			var addrs []string
			for _, addr := range ethernet.NameServers.Addresses {
				addrs = append(addrs, addr.String())
			}
			update("Network", "DNS", strings.Join(addrs, " "))
		}

		if len(config) == 0 {
			continue
		}

		slog.InfoContext(ctx, "configuring network interface", "interface", name)

		builder := &strings.Builder{}
		for section, items := range config {
			if _, err := fmt.Fprintf(builder, "[%s]\n", section); err != nil {
				return nil, err
			}
			for k, v := range items {
				if _, err := fmt.Fprintf(builder, "%s=%s\n", k, v); err != nil {
					return nil, err
				}
			}
		}
		outPath := fmt.Sprintf("/run/systemd/network/%s.network", name)
		if err := os.WriteFile(outPath, []byte(builder.String()), 0o644); err != nil {
			return nil, fmt.Errorf("failed to write %q network config: %w", name, err)
		}
		hasChanges = true
	}

	if hasChanges {
		return []string{"systemd-networkd.service"}, nil
	}
	return nil, nil
}
