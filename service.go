package main

import (
	"fmt"
	"os"
	"path/filepath"
	"text/template"
)

const plistTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.readitsoon.companion</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{.BinaryPath}}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>`

func installLaunchAgent() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	launchAgentsDir := filepath.Join(home, "Library", "LaunchAgents")
	if err := os.MkdirAll(launchAgentsDir, 0755); err != nil {
		return err
	}

	plistPath := filepath.Join(launchAgentsDir, "com.readitsoon.companion.plist")

	binaryPath, err := os.Executable()
	if err != nil {
		return err
	}

	tmpl, err := template.New("plist").Parse(plistTemplate)
	if err != nil {
		return err
	}

	f, err := os.Create(plistPath)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := tmpl.Execute(f, struct{ BinaryPath string }{binaryPath}); err != nil {
		return err
	}

	fmt.Printf("Service installed at %s\n", plistPath)
	fmt.Println("It will start automatically on next login.")
	return nil
}
