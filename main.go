package main

import (
	"fmt"
	"os"
)

var (
	baseURL   string
	userEmail string
	authToken string
)

func main() {
	if baseURL == "" || userEmail == "" || authToken == "" {
		fmt.Fprintln(os.Stderr, "Error: this binary was not compiled with required credentials.")
		fmt.Fprintln(os.Stderr, "Download from your ReadItSoon account.")
		os.Exit(1)
	}

	cfg, err := loadOrCreateConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Config error: %v\n", err)
		os.Exit(1)
	}

	if cfg.SavePath == "" {
		cfg.SavePath, err = promptSavePath()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		if err := cfg.save(); err != nil {
			fmt.Fprintf(os.Stderr, "Error saving config: %v\n", err)
			os.Exit(1)
		}
	}

	if !cfg.ServiceInstalled {
		if promptInstallService() {
			if err := installLaunchAgent(); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not install service: %v\n", err)
			} else {
				cfg.ServiceInstalled = true
				cfg.save()
			}
		}
	}

	runMenuBar(cfg)
}
