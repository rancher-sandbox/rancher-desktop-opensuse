package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/goccy/go-yaml"
)

// Escape the name of a mount point systemd-style; see systemd.unit(5)
func escapeSystemdMountName(input string) string {
	input = filepath.Clean(input)
	input = strings.Trim(input, "/")
	if input == "" {
		return "-" // Special case for the root directory
	}
	var builder strings.Builder
	for _, r := range input {
		switch {
		case r == '/':
			builder.WriteRune('-')
		case 'A' <= r && r <= 'Z', 'a' <= r && r <= 'z', '0' <= r && r <= '9':
			builder.WriteRune(r)
		case r == ':', r == '_', r == '.':
			builder.WriteRune(r)
		default:
			builder.WriteString(fmt.Sprintf("\\x%02x", r))
		}
	}
	result := builder.String()
	if strings.HasPrefix(result, ".") {
		return "\\x2e" + result[1:]
	}
	return result
}

// Load /mnt/lima-cidata/user-data; returns a list of systemd units that must
// be started after.
func LoadUserData(ctx context.Context) ([]string, error) {
	var units []string

	var userData struct {
		Users []struct {
			Name                      string   `yaml:"name"`
			UID                       string   `yaml:"uid"`
			GECOS                     string   `yaml:"gecos"`
			HomeDir                   string   `yaml:"homedir"`
			Shell                     string   `yaml:"shell"`
			Sudo                      string   `yaml:"sudo"`
			LockPasswd                bool     `yaml:"lock_passwd"`
			SSHAuthorizedKeys         []string `yaml:"ssh_authorized_keys"`
			SSHAuthorizedKeysFallback []string `yaml:"ssh-authorized-keys"`
		} `yaml:"users"`
		Mounts     [][]string `yaml:"mounts"`
		WriteFiles []struct {
			Content     string `yaml:"content"`
			Owner       string `yaml:"owner"`
			Path        string `yaml:"path"`
			Permissions string `yaml:"permissions"`
		} `yaml:"write_files"`
		ManageResolveConf bool `yaml:"manage_resolv_conf"`
		ResolveConf struct {
			NameServers []string `yaml:"nameservers"`
		} `yaml:"resolv_conf"`
	}

	file, err := os.Open("/mnt/lima-cidata/user-data")
	if err != nil {
		return nil, fmt.Errorf("failed to read user-data: %w", err)
	}
	defer file.Close()

	if err := yaml.NewDecoder(file).DecodeContext(ctx, &userData); err != nil {
		return nil, fmt.Errorf("failed to unmarshal user-data: %w", err)
	}

	// Process users
	for _, userEntry := range userData.Users {
		// Create user
		slog.InfoContext(ctx, "creating user", "user", userEntry.Name)
		err = runCommand(ctx, "/usr/sbin/useradd",
			"--home-dir", userEntry.HomeDir,
			"--create-home",
			"--comment", userEntry.GECOS,
			"--uid", userEntry.UID,
			"--shell", userEntry.Shell,
			userEntry.Name)
		if err != nil {
			return nil, fmt.Errorf("failed to create user %q: %w", userEntry.Name, err)
		}

		// Look up the newly created user
		userInfo, err := user.LookupId(userEntry.UID)
		if err != nil {
			return nil, fmt.Errorf("failed to look up newly created user %q: %w", userEntry.Name, err)
		}
		uid, err := strconv.ParseInt(userInfo.Uid, 10, 32)
		if err != nil {
			return nil, fmt.Errorf("failed to parse user %q uid %q: %w", userEntry.Name, userInfo.Uid, err)
		}
		gid, err := strconv.ParseInt(userInfo.Gid, 10, 32)
		if err != nil {
			return nil, fmt.Errorf("failed to parse user %q gid %q: %w", userEntry.Name, userInfo.Gid, err)
		}

		// Add user to sudoers
		if userEntry.Sudo != "" {
			slog.InfoContext(ctx, "adding user to sudoers", "user", userEntry.Name)
			err := os.WriteFile(
				fmt.Sprintf("/etc/sudoers.d/90-lima-user-%s", userEntry.Name),
				[]byte(userEntry.Name + " " + userEntry.Sudo),
				0o644)
			if err != nil {
				return nil, fmt.Errorf("failed to create sudoers file for %q: %w", userEntry.Name, err)
			}
		}

		// Create authorized_keys
		slog.InfoContext(ctx, "creating authorized_keys", "user", userEntry.Name)
		sshDir := filepath.Join(userEntry.HomeDir, ".ssh")
		if err := os.MkdirAll(sshDir, 0o700); err != nil {
			return nil, fmt.Errorf("failed to create %q .ssh: %w", userEntry.Name, err)
		}
		if err := os.Chown(sshDir, int(uid), int(gid)); err != nil {
			return nil, err
		}
		sshAuthorizedKeys := append(userEntry.SSHAuthorizedKeys, userEntry.SSHAuthorizedKeysFallback...)
		err = os.WriteFile(
			filepath.Join(sshDir, "authorized_keys"),
			[]byte(strings.Join(sshAuthorizedKeys, "\n")),
			0o600)
		if err != nil {
			return nil, fmt.Errorf("failed to write %q authorized_keys: %w", userEntry.Name, err)
		}
		if err := os.Chown(filepath.Join(sshDir, "authorized_keys"), int(uid), int(gid)); err != nil {
			return nil, err
		}
	}

	// Process mounts
	for i, mount := range userData.Mounts {
		if len(mount) < 2 {
			return nil, fmt.Errorf("mount #%d is too short: %+v", i, mount)
		}
		slog.InfoContext(ctx, "creating mount", "where", mount[1], "what", mount[0])
		lines := []string{
			"[Unit]",
			"After=local-fs.target",
			"[Install]",
			"WantedBy=default.target",
			"[Mount]",
			fmt.Sprintf("What=%s", mount[0]),
			fmt.Sprintf("Where=%s", mount[1]),
		}
		if len(mount) > 2 {
			lines = append(lines, fmt.Sprintf("Type=%s", mount[2]))
		}
		if len(mount) > 3 {
			lines = append(lines, fmt.Sprintf("Options=%s", mount[3]))
		}
		output := []byte(strings.Join(append(lines, ""), "\n"))
		filename := filepath.Join("/run/systemd/system", escapeSystemdMountName(mount[1])+".mount")
		if err := os.WriteFile(filename, output, 0o644); err != nil {
			return nil, fmt.Errorf("failed to create mount unit %q: %w", filename, err)
		}
		units = append(units, escapeSystemdMountName(mount[1]) + ".mount")
	}

	// Process files
	for _, writeFile := range userData.WriteFiles {
		slog.InfoContext(ctx, "writing file", "path", writeFile.Path)
		fileMode, err := strconv.ParseUint(writeFile.Permissions, 8, 32)
		if err != nil {
			return nil, fmt.Errorf("failed to parse permissions for %s: %w", writeFile.Path, err)
		}
		if err := os.MkdirAll(filepath.Dir(writeFile.Path), 0o755); err != nil {
			return nil, fmt.Errorf("failed to create directory for %s: %w", writeFile.Path, err)
		}
		if err := os.WriteFile(writeFile.Path, []byte(writeFile.Content), os.FileMode(fileMode)); err != nil {
			return nil, fmt.Errorf("failed to write file %s: %w", writeFile.Path, err)
		}
		uid := int64(-1)
		gid := int64(-1)
		userName, groupName, _ := strings.Cut(writeFile.Owner, ":")
		if u, err := user.Lookup(userName); err != nil {
			return nil, fmt.Errorf("failed to write file %s: failed to lookup user %s: %w", writeFile.Path, userName, err)
		} else if uid, err = strconv.ParseInt(u.Uid, 10, 32); err != nil {
			return nil, fmt.Errorf("failed to write file %s: user %s has non-numeric uid %s", writeFile.Path, userName, u.Uid)
		}
		if groupName != "" {
			if g, err := user.LookupGroup(groupName); err != nil {
				return nil, fmt.Errorf("failed to write file %s: failed to lookup group %s: %w", writeFile.Path, groupName, err)
			} else if gid, err = strconv.ParseInt(g.Gid, 10, 32); err != nil {
				return nil, fmt.Errorf("failed to write file %s: group %s has non-numeric gid %s", writeFile.Path, groupName, g.Gid)
			}
		}
		if err := os.Chown(writeFile.Path, int(uid), int(gid)); err != nil {
			return nil, fmt.Errorf("failed to change file %s owner: %w", writeFile.Path, err)
		}
	}

	// Process name server overrides
	if userData.ManageResolveConf {
		slog.InfoContext(ctx, "updating name servers", "name servers", userData.ResolveConf.NameServers)
		contents := fmt.Sprintf("[Resolve]\nDNS=%s\n", strings.Join(userData.ResolveConf.NameServers, " "))
		filePath := "/run/systemd/resolved.conf.d/10-rd-init.conf"
		if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(filePath, []byte(contents), 0o644); err != nil {
			return nil, err
		}
	}

	return units, nil
}
