// Command rd-init is a minimal implementation of cloud-init to start lima.
// Note that this only implements `cloud-init-local`.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"

	"github.com/coreos/go-systemd/daemon"
	"github.com/coreos/go-systemd/v22/dbus"
)

func runCommand(ctx context.Context, name string, arg... string) error {
	slog.DebugContext(ctx, "Running command", "name", name, "arg", arg)
	cmd := exec.CommandContext(ctx, name, arg...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func run(ctx context.Context) error {
	var units []string
	fns := []func(context.Context)([]string, error) {
		LoadMetadata,
		LoadUserData,
		LoadNetworkConfig,
	}
	for _, fn := range fns {
		if newUnits, err := fn(ctx); err != nil {
			return err
		} else {
			units = append(units, newUnits...)
		}
	}

	slog.InfoContext(ctx, "reloading systemd", "units", units)

	conn, err := dbus.NewSystemConnectionContext(ctx)
	if err != nil {
		return fmt.Errorf("failed to connect to systemd: %w", err)
	}
	defer conn.Close()

	if err := conn.ReloadContext(ctx); err != nil {
		return fmt.Errorf("failed to reload systemd: %w", err)
	}

	// Trigger udevadm to cause the network interface to change name.
	slog.InfoContext(ctx, "triggering udevadm to rename interfaces")
	if err := runCommand(ctx, "/usr/bin/udevadm", "control", "--reload"); err != nil {
		return fmt.Errorf("failed to reload udev: %w", err)
	}
	err = runCommand(ctx, "/usr/bin/udevadm", "trigger", "--type=devices", "--subsystem-match=net")
	if err != nil {
		return fmt.Errorf("failed to rename network devices: %w", err)
	}

	// Notify ready before we reload the other units; otherwise we end up
	// blocking startup due to a loop with systemd-networkd.
	if _, err := daemon.SdNotify(true, daemon.SdNotifyReady); err != nil {
		return err
	}

	seenUnits := make(map[string]bool)
	for _, unit := range units {
		if seenUnits[unit] {
			continue
		}
		seenUnits[unit] = true
		ch := make(chan string)
		_, err = conn.RestartUnitContext(ctx, unit, "replace", ch)
		if err != nil {
			return fmt.Errorf("failed to start unit %s: %w", unit, err)
		}
		slog.InfoContext(ctx, "restarted systemd unit", "unit", unit, "result", <-ch)
	}

	return nil
}

func main () {
	ctx := context.Background()
	if err := run(ctx); err != nil {
		slog.ErrorContext(ctx, "rd-init failed", "error", err)
		os.Exit(1)
	}
}
