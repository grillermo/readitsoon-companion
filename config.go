package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	SavePath         string `json:"save_path"`
	ServiceInstalled bool   `json:"service_installed"`
	path             string
}

func configPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".readitsoon-companion.json")
}

func loadOrCreateConfig() (*Config, error) {
	path := configPath()
	cfg := &Config{path: path}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	cfg.path = path
	return cfg, nil
}

func (c *Config) save() error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.path, data, 0644)
}

func promptSavePath() (string, error) {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Where should ReadItSoon save markdown files? (absolute path): ")
	path, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	path = strings.TrimSpace(path)

	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("path must be absolute: %s", path)
	}

	if err := os.MkdirAll(path, 0755); err != nil {
		return "", fmt.Errorf("cannot create directory: %w", err)
	}

	return path, nil
}

func promptInstallService() bool {
	reader := bufio.NewReader(os.Stdin)
	fmt.Print("Install as background service (runs on login)? [y/n]: ")
	answer, _ := reader.ReadString('\n')
	return strings.TrimSpace(strings.ToLower(answer)) == "y"
}
