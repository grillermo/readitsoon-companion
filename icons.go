package main

import _ "embed"

//go:embed assets/icon-22.png
var iconDefault []byte

// Same icon for all states — tooltip changes to show status
var iconDownloading []byte
var iconDone []byte

func init() {
	iconDownloading = iconDefault
	iconDone = iconDefault
}
